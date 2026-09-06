# 決定記録

検討の過程で却下した案とその理由。**同じ議論を繰り返さないための記録**。

---

## D1. 検索を OpenSearch に分離する(CQRS 的分離)

**採用。**

物件検索は複数条件のフィルタリング + 全文検索 + ソートが重なり、RDB の WHERE 句と
JOIN が遅くなりやすい典型例。大手不動産サービスも同様に検索エンジンを別立てにしている。

**ただし前提条件がある**: 導入前に、スロークエリログと DB の CPU/IO 使用率で
ボトルネックを実測すること。適切な複合インデックスやリードレプリカで足りるなら過剰設計になる。
この検証は「使えるか」を確かめるものであって、「使うべき」の証明ではない。

---

## D2. DMS のターゲットを OpenSearch ではなく Kinesis にする

**採用。**

却下した案: DMS → OpenSearch 直結。

DMS の OpenSearch ターゲットは 1テーブル = 1インデックスの単純マッピングが基本で、
複数テーブルを JOIN して1ドキュメントにする変換ができない。
テーブルごとにインデックスを分けて検索時に結合する案もあるが、クエリが複雑になりすぎる。

DMS → Kinesis → Lambda(非正規化)→ OpenSearch とすることで、
Lambda で関連テーブルを引き直して非正規化したドキュメントを組み立てられる。

---

## D3. 同期方法として after_commit / 定期バッチではなく CDC を選ぶ

**採用。**

却下した案:

- **after_commit での同期更新** — 書き込みのたびに OpenSearch への遅延が API レスポンスに乗る
- **ActiveJob 非同期更新** — 実装は楽だが、更新経路が複数(バッチ、管理画面、外部連携)ある場合に
  同期漏れが起きやすい
- **定期バッチのみ** — 即時反映ができない

CDC はアプリケーションコードを汚さず、更新経路が複数あっても取りこぼさない。
ただし**定期フルリインデックスは保険として併用する**(D6)。

---

## D4. ローカル検証で LocalStack の DMS を使わない

**採用(2026-09)。**

LocalStack の DMS プロバイダは調査の結果、以下の制約があった。

- **最上位プラン(Ultimate)限定**。個人の技術検証で払う額ではない
- プレビュー状態
- ターゲットは Kinesis のみ。OpenSearch ターゲットは存在しない
- Aurora MySQL がサポート対象リストにない
- `full-load` と `cdc` を**同時に実行できない**。本番で使う「Full load + CDC」が未実装
- テーブルマッピングの `transformation` ルールが未サポート

参考: https://docs.localstack.cloud/aws/services/dms/

---

## D5. Debezium も使わず、DMS 形式イベントをフィクスチャで流す

**採用(2026-09)。**

却下した案: Debezium(Kafka Connect)で CDC を再現する。

Debezium は無料で成熟しており、binlog 周りの挙動は本物に近い。
しかし**イベント形式が DMS と異なる**(Debezium は `before`/`after`/`op`、
DMS は `data`/`metadata`)ため、Lambda のパース処理が本番へ移植できない。
加えて Kafka + Connect + consumer の3サービスが増え、当初の「サービスを分散させたくない」
という動機に反する。

代わりに、DMS 形式の JSON をフィクスチャとして `aws kinesis put-record` で直接流す。

**この判断の根拠**: 検証で価値があるのは ①マッピング設計 ②Query DSL ③非正規化ロジック
④イベントパース の4点。binlog 設定の正しさ・同期ラグ・障害復旧は、ローカルの模倣物で
測っても本番の参考値にならないので、AWS の検証アカウントで確認する。

**この決定の帰結**: Kinesis に流すイベントは必ず AWS DMS の形式に合わせること。
Debezium 形式にしてはいけない。フィクスチャは `reference/dms-event-samples/` に置く。

---

## D6. CDC と定期フルリインデックスを併用する

**採用。**

CDC は DMS タスクの一時停止・エラー・binlog 保持期間超過で取りこぼしが起きうる。
CDC を「リアルタイム反映用」、バッチリインデックスを「整合性の保険」とする二段構えにする。

---

## D7. インデックスにエイリアスを噛ませる

**採用。**

OpenSearch のマッピングは作成後に変更できない項目が多い。
実インデックスを `properties_v1`, `properties_v2` … とし、アプリは
`properties_search` エイリアスだけを見る。新インデックスに流し直してエイリアスを
張り替えることで無停止入れ替えができる。

---

## D8. IaC(CDK / Terraform)を使わない

**採用。**

検証の本筋ではなく、セットアップの複雑さが増すだけ。AWS CLI を叩くシェルスクリプトで済ませる。
本番構築時に改めて IaC 化する。

---

## D9. LocalStack の無料アカウント auth token を `.env` で使う

**採用(2026-09)。**

2026-03 の Community/Pro イメージ統合以降、`localstack/localstack` イメージは
`LOCALSTACK_AUTH_TOKEN` が環境変数にないと起動時にライセンス確認で落ちるようになった
(exit code 55, "License activation failed")。一時的な回避策として
`LOCALSTACK_ACKNOWLEDGE_ACCOUNT_REQUIREMENT=1` があったが 2026-04 に失効している。

**これは有料機能の利用ではない。** app.localstack.cloud で無料登録すれば取得できる
account-based token であり、opensearch / kinesis / lambda / secretsmanager は
引き続き無料範囲(`_localstack/health` で `available`)で動く。DMS のような
Ultimate 限定機能(D4)とは別種の制約。

対応: 無料アカウントで発行した token を `.env` の `LOCALSTACK_AUTH_TOKEN` に設定し、
`docker-compose.yml` から渡す。`.env` は元々 `.gitignore` 対象(@CLAUDE.md)なので
運用上の変更はない。

---

## D10. `ja_text` アナライザーから `icu_normalizer` を外す

**採用(2026-09)。**

@reference/index-mapping.json の `ja_text` カスタムアナライザーは元々
`icu_normalizer`(全角/半角、カタカナ長音などの表記ゆれ正規化)を char_filter に
含んでいたが、LocalStack の OpenSearch には `analysis-icu` プラグインが同梱されておらず
(`_cat/plugins` で確認済み。kuromoji は同梱されているが icu は別プラグイン)、
インデックス作成が `illegal_argument_exception` で失敗した。

却下した案: カスタム Docker イメージで `analysis-icu` を追加インストールする。
検証の本筋(マッピング設計・Query DSL・非正規化ロジック・イベントパース)から外れ、
1コンテナで完結する構成の単純さが損なわれる。

対応として `icu_normalizer` を char_filter から削除した。この結果、
@docs/verification-plan.md の V1 のうち「表記ゆれ(全角/半角、カタカナ長音)の正規化」は
ローカルでは検証できない。本番導入時は AWS OpenSearch Service に
Analysis-ICU パッケージを関連付けることで同等の機能を追加できるため、
機能自体を諦めたわけではなく、ローカル検証環境の制約として扱う。

---

## D11. LocalStack の OpenSearch ドメインは永続化しない前提で運用する

**採用(2026-09)。**

`_localstack/health` の `features.persistence` が `disabled` になっており、
`docker compose down` や `localstack` コンテナの再作成(設定変更による recreate 含む)で
OpenSearch ドメインの中身が消える(MySQL 側は別コンテナ・別ボリュームなので影響を受けない)。

永続化には Pro 版の機能が絡む可能性があり、深追いしない。
その代わり `create-domain.sh` → `create-index.sh` → `full-reindex.sh` を
再実行すれば数秒で元の状態に戻せるよう、各スクリプトを冪等に近い形(既存インデックス削除は
別コマンド、エイリアス張り替えは何度実行しても安全)に保っている。
LocalStack を再起動したら、まずこの3コマンドを流し直すことを前提とする。

---

## D12. Lambda の mysql2 は Lambda 実行環境イメージ内でビルドし、libmysqlclient を同梱する

**採用(2026-09)。**

`mysql2` はネイティブ拡張(C コンパイル済みバイナリ)の gem で、Linux 向けの
precompiled gem は rubygems 上に存在しない(Windows 向けのみ)。macOS でビルドした
gem は Lambda(Linux/aarch64)では動かないため、`public.ecr.aws/lambda/ruby:3.2`
(LocalStack が実行時に使うのと同じベースイメージ)の中で `bundle install` してビルドする。

このイメージには gcc/make/mysql ヘッダが入っておらず、`mariadb-devel` を yum で入れようとすると
Amazon 独自の `openssl-snapsafe-libs` パッケージと `openssl-libs` が Conflicts 指定されていて
インストールできない。`yumdownloader` で RPM 本体だけ取得し、`rpm -Uvh --force --nodeps` で
依存関係チェックと衝突チェックを無視して強制インストールすることで回避した
(この操作はビルド用の使い捨てコンテナ内だけで完結し、実行環境やホストには影響しない)。

ビルドした `mysql2.so` は `libmysqlclient.so.18` に動的リンクするが、この共有ライブラリは
Lambda の実行環境イメージにプリインストールされていない(ビルドに使った他の依存ライブラリは
ベースイメージに標準で入っている)。そのため `libmysqlclient.so.18` だけを zip に同梱し、
`LD_LIBRARY_PATH=/var/task/vendor/native` を Lambda の環境変数に設定して読み込ませる
(deploy-lambda.sh 参照)。

**副次的に踏んだ問題**: MySQL 8.0 のデフォルト認証方式 `caching_sha2_password` に、
Amazon Linux 2 の古い mariadb クライアントライブラリ(5.5系)が対応しておらず、
Lambda からの接続が `Authentication plugin 'caching_sha2_password' cannot be loaded` で
失敗した。`mysql/conf.d/binlog.cnf` に `default_authentication_plugin = mysql_native_password`
を追加して解決した。

---

## D13. 物件登録 API のリクエスト形式は JSON のみにする(protobuf は使わない)

**採用(2026-09)。**

却下した案: `POST /properties` を protobuf(またはJSON/protobuf 両対応)にする。

protobuf の契約が守るのはクライアント → Rails の1ホップだけで、その先は
MySQL の列 → binlog → **DMS が出力する JSON 形式**(D5 で確定済み)に変換される。
つまりパイプライン全体を見たときに protobuf の型安全性は伝播せず、恩恵が範囲に対して薄い。

加えてこの検証の主題は検索(読み取り)側であり、登録側の転送効率・スキーマ進化は
論点になっていない。JSON であれば curl で中身をそのまま読めることも、
このリポジトリの「検証結果を実測値で示す」という性質(@docs/verification-plan.md)に合う。

---

## D14. Rails の after_commit で CDC イベントを発火するのは D3 の判断を覆すものではない

**採用(2026-09)。**

@app/models/concerns/emits_cdc_event.rb(api/)は `after_commit` から Kinesis に
put-record している。これは一見 D3 で却下した「after_commit での同期更新」に見えるが、
狙いが異なる。

D3 が却下したのは「**書き込みのたびに OpenSearch への反映を同期的に待つ**」構成
(API レスポンスが検索インデックス更新の完了を待ってしまう)。
D14 の after_commit は **本番では DMS が binlog を検知して行う役割をローカルで肩代わり
しているだけ**で、Kinesis への put-record 自体は投げっぱなし(レスポンスは待たない)。
Kinesis 以降(Lambda → OpenSearch)の非同期性は D3 の設計のまま変わっていない。

put-record が失敗しても書き込みそのものは失敗させず、ログに残すだけにしている
(`EmitsCdcEvent#emit_cdc_event` の rescue 節)。本番の DMS も CDC 基盤の不調で
アプリの書き込みを止めることはないため、この非依存性を再現している。

---

## D15. api/ のスキーマ管理を reference/schema.sql から Rails + Ridgepole に変更する

**採用(2026-09)。**

これまで `reference/schema.sql`(`mysql/init/01_schema.sql` に複製)を正のスキーマ定義とし、
Rails 側はマイグレーションを持たない方針だった。これは「検索基盤の検証に集中し、Rails 側は
薄く保つ」という当初のスコープに沿ったものだったが、今回 Rails 側のスキーマ管理・テスト・型定義の
開発体験そのものも検証対象に含めることにしたため、スキーマの正を `api/db/Schemafile` に移し、
Ridgepole(`bundle exec rake ridgepole:apply[env]`)で適用する方式に変更した。

`reference/schema.sql` と `mysql/init/01_schema.sql` は削除し、シードデータは `api/db/seeds.rb` に
移植した。MySQL コンテナの初期化は空データベースの作成(`property_dev` は `MYSQL_DATABASE` 環境変数、
`property_test` は `mysql/init/02_test_database.sql`)のみを担い、テーブル定義は持たない。

**この決定の影響範囲**: これはあくまで `api/` 内のスキーマ管理方法の変更であり、
D1〜D14 で決めた CDC / DMS / Kinesis / Lambda まわりの構成には影響しない。
DMS 形式のイベント(`data`/`metadata`)や非正規化ロジックは従来通り。

---

## D16. RSpec のテスト DB(property_test)を development(property_dev)と分離する

**採用(2026-09)。**

RSpec 導入にあたり、`config/database.yml` の `test` 環境が `development` と同じデータベース
(`property_dev`)を指していた点を見直した。共用のままだとテスト実行のたびに開発用のシードデータが
巻き込まれる/汚れるおそれがあるため、`property_test` を新設して分離した。

副作用として、`app` ユーザーは MySQL コンテナ起動時に `MYSQL_DATABASE`(property_dev)にしか
権限を持たない(公式 MySQL イメージの仕様)ため、`property_test` に対する
`GRANT ALL PRIVILEGES` を別途行う必要があった(`mysql/init/02_test_database.sql` /
`scripts/setup-mysql.sh`)。ローカル検証環境のみの対応であり、本番の権限設計とは無関係。

また RSpec のモデル・CDC 関連のテストが LocalStack の起動を前提にしないよう、
`api/app/lib/cdc.rb` の Kinesis クライアントに `stub_responses: Rails.env.test?` を渡し、
test 環境では実際に put-record しない(AWS SDK 組み込みのスタブ機構を使う)ようにした。

---

## D17. Ridgepole / rbs-inline / rbs_rails 導入時に踏んだ問題

**記録(2026-09)。** D15/D16 の導入作業中に踏んだ、次に同じ調査をしなくて済むようにするための記録。

- **Ridgepole で `created_at`/`updated_at` に `default: -> { "CURRENT_TIMESTAMP" }` を指定すると
  `Mysql2::Error: Invalid default value` で `--apply` が失敗する**。既存カラムとの差分を
  `change_column` で当てる経路では、この関数デフォルトが正しく解釈されず生の文字列として
  送られてしまう。ActiveRecord は保存のたびに created_at/updated_at を明示的にセットするため、
  DB レベルの `DEFAULT`/`ON UPDATE CURRENT_TIMESTAMP` は実質不要と判断し、
  素の `t.timestamps null: false` に変更して回避した(`api/db/Schemafile`)
- **rbs-inline はデフォルトが `--opt-in`** で、ファイルの先頭に `# rbs_inline: enabled` コメントが
  ないと `#:` アノテーションを無視する(`rbs-inline --output=... app lib` を実行しても
  0ファイルしか生成されない)。マーカーをファイルごとに書き足す運用は避け、
  `--opt-out`(デフォルトで全ファイルを対象にし、除外したいファイルだけ
  `# rbs_inline: disabled` を書く)を使うことにした(`api/lib/tasks/rbs.rake`)
- **rbs_rails が生成する RBS は `ActiveRecord::Base`, `ActionController::API` などコア型を
  参照するが、`rbs` gem 単体にはこれらの sig が含まれていない**。`bundle exec rbs collection init`
  → `bundle exec rbs collection install` で `ruby/gem_rbs_collection` から
  activerecord/actionpack/activesupport 等の RBS を取得する必要がある。
  取得先の `api/.gem_rbs_collection/` は `rbs_collection.lock.yaml` から再現可能なため `.gitignore` 対象にした
- **Rake の制限**: `bundle exec rake "ridgepole:apply[development]" "ridgepole:apply[test]"` のように
  同じ引数付きタスクを1回の rake 呼び出しで2回指定しても、Rake は「同じタスクの2回目の invoke」を
  (引数が違っても)無視して1回しか実行しない。`scripts/setup-mysql.sh` では
  `bundle exec rake` の呼び出し自体を development 用・test 用で2プロセスに分けて回避した
