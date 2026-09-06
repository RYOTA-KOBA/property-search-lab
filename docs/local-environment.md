# ローカル検証環境

## 構成

LocalStack Community(無料)と素の MySQL コンテナを組み合わせるハイブリッド構成。

```
[LocalStack Community : 1コンテナ]
    OpenSearch  +  Kinesis  +  Lambda  +  Secrets Manager  +  Logs
[素の Docker]
    MySQL 8.0 (binlog=ROW)
[ホストで直接起動]
    Rails API(api/)                … 登録・検索のインターフェース
    フルリインデックス / 検索確認用 Ruby スクリプト(scripts/)
```

## 本番との対応関係

| 本番 (AWS) | ローカル | 検証できること |
|---|---|---|
| Rails(登録・検索 API) | `api/` の Rails(ホストで直接起動) | API の責務分割(検索は OpenSearch、詳細は MySQL) |
| Aurora MySQL | MySQL 8.0 コンテナ | スキーマ設計、binlog 前提条件 |
| DMS レプリケーションインスタンス | **再現しない**。物件登録 API は `after_commit` で代わりにイベントを流す(D14)。SQL を直接叩いた場合は `scripts/emit-cdc-event.sh` で手動送出 | — |
| Kinesis Data Streams | LocalStack Kinesis | ストリーム経由の配送 |
| Lambda(非正規化) | LocalStack Lambda | **非正規化ロジックとイベントパース** |
| Amazon OpenSearch Service | LocalStack OpenSearch | マッピング、Query DSL、エイリアス運用 |
| Sidekiq 定期ジョブ | ローカル Ruby スクリプト(`full-reindex.sh`) | 全件再投入 |

## CDC 部分を再現しない理由

LocalStack の DMS プロバイダは**最上位プラン(Ultimate)限定**かつプレビュー状態で、
以下の制約がある。

- ターゲットは Kinesis のみ。OpenSearch ターゲットは存在しない
- Aurora MySQL がサポート対象リストにない(RDS MySQL / 外部 MySQL のみ)
- レプリケーションタスクは `full-load` か `cdc` の**どちらか一方**しか動かない。
  本番で使う「Full load + CDC」の組み合わせが未実装
- テーブルマッピングの `"rule-type": "transformation"` が未サポート

一方、Debezium を代替に使う案もあるが、イベント形式が DMS と異なるため
Lambda のパース処理が本番へ移植できない。

そこで **DMS 形式の JSON をフィクスチャとして直接 Kinesis に put-record する**方針を採る。
検証で本当に価値があるのはマッピング設計・Query DSL・非正規化ロジック・イベントパースの4点であり、
binlog 設定の正しさや同期ラグの実測は、ローカルの模倣物で測っても本番の参考値にならない。
それらは AWS の検証アカウントで小さく DMS タスクを1本立てて確認するほうが安く早い。

判断の経緯は @docs/decisions.md を参照。

## セットアップの想定手順

```bash
cp .env.example .env
docker compose up -d

./scripts/setup-mysql.sh        # property_test 作成 + Ridgepole でスキーマ適用(dev/test) + シードデータ投入
./scripts/create-domain.sh      # OpenSearch ドメイン作成
./scripts/create-index.sh v1    # インデックス作成 + エイリアス張り替え
./scripts/deploy-lambda.sh      # Lambda 作成 + Kinesis イベントソースマッピング
./scripts/full-reindex.sh       # MySQL から全件を非正規化して投入

# 別端末で CDC ログを追尾しておくと登録の反映が見える
./scripts/tail-cdc.sh

# 別端末で API を起動(ホストで直接。docker-compose には加えない)
cd api && bundle install && bin/rails s

./scripts/search-examples.sh    # 各種クエリの動作確認(scripts 経由)
./scripts/emit-cdc-event.sh update properties 1   # SQL を直接いじった場合の手動送出
```

`api/db/Schemafile` を変更したときは `bundle exec rake ridgepole:apply[development]` /
`[test]` の両方を流し、`property_dev` と `property_test` の両方に反映すること。

## api/ のテスト・型定義

```bash
cd api
bundle exec rspec                          # LocalStack が起動していなくても通る(Cdc をスタブ化しているため)

# 初回のみ: rails/activerecord 等サードパーティ gem の RBS を取得する(.gem_rbs_collection/ は .gitignore 対象)
bundle exec rbs collection install

bundle exec rake rbs:generate              # rbs-inline / rbs_rails で sig/ 配下を再生成
bundle exec steep check                    # 型検査
```

## 環境固有の注意点

- Linux では OpenSearch 起動前に `sudo sysctl -w vm.max_map_count=262144` が必要
- LocalStack の OpenSearch には analysis-kuromoji がデフォルトで同梱されているため、
  プラグインの追加インストールは不要
- LocalStack の RDS プロバイダは有料機能。MySQL は素のコンテナを使う。
  DMS 的にも「外部 MySQL」は正規のソース種別なので、設計上の妥協にはならない
- LocalStack のエンドポイントは `http://localhost:4566`。
  OpenSearch ドメインは作成後に払い出される個別のエンドポイントを使う

## 使わないもの

- CDK / Terraform — 検証の本筋ではなく、セットアップの複雑さが増すだけ。
  AWS CLI を叩くシェルスクリプトで済ませる
- LocalStack Pro / Ultimate の機能全般
