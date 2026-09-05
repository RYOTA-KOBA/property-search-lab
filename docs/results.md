# 検証結果

@docs/verification-plan.md の V1〜V7 の結果と、最終的な判断を記録する。
検証日: 2026-09-06。環境: LocalStack 2026.8.1(無料アカウント token 使用)、
MySQL 8.0、OpenSearch 2.11.1(kuromoji 同梱)。

## V1. マッピング設計が意図通りか — **合格(一部保留)**

- 「王子神谷」→「王子」「神谷」、「レジデンス」は1トークンに分割され、意図した粒度だった
- `dynamic: strict` は未定義フィールド(`unknown_field`)を含むドキュメントの投入を
  `strict_dynamic_mapping_exception` で拒否した
- **保留**: 表記ゆれ(全角/半角、カタカナ長音)の正規化は `icu_normalizer` が必要だが、
  LocalStack の OpenSearch に `analysis-icu` プラグインが同梱されておらず検証できなかった
  (@docs/decisions.md の D10)。本番の AWS OpenSearch Service では Analysis-ICU パッケージを
  追加すれば同じ設定のまま使えるはずだが、実機での確認は未実施

## V2. 検索クエリが表現しきれるか — **合格**

@reference/index-mapping.json のマッピングに対し、6要件すべてが単一クエリで
意図した結果を返した(`scripts/search-examples.sh`)。

| # | 要件 | 結果 |
|---|---|---|
| 1 | 価格帯+間取り+徒歩分数の複合絞り込み | 合格(2件ヒット、想定通り) |
| 2 | 指定地点からN km圏内、近い順 | 合格(`_geo_distance` sort で距離順に整列) |
| 3 | 物件名・住所の日本語全文検索 | 合格(kuromoji で「神谷」がヒット) |
| 4 | 特定路線かつ徒歩5分以内の駅を持つ物件 | 合格。`nested` を使わずフラットな filter にすると
      「別々の駅の条件」を組み合わせて誤ヒットする反例(4b)も確認し、`nested` が
      必要である根拠を得た |
| 5 | 間取りごとの件数、価格帯ヒストグラム | 合格(terms/range aggregation) |
| 6 | 非公開物件の除外 | 合格(`term` filter) |

## V3. 非正規化ロジックが成立するか — **合格**

`property_stations` に新しい駅(徒歩3分)を追加 → `emit-cdc-event.sh` で CDC イベントを
Kinesis に put-record → **LocalStack にデプロイした実際の Lambda** が処理し、
物件ドキュメントの `min_walk_minutes` が更新されることを確認した
(6分→5分、8分→3分など、複数回のテストで再現)。

これは DMS 単体(1テーブル=1インデックス)では実現できない部分であり、
Lambda を挟む構成(@docs/decisions.md の D2)の妥当性を裏付ける結果。

## V4. DMS イベント形式のパースが正しいか — **合格**

@reference/dms-event-samples/ の4種類のイベントをすべて Kinesis に put-record し、
Lambda(CloudWatch Logs で確認)の挙動を検証した。

- `operation: insert / update` → ドキュメントが upsert される(合格)
- `operation: delete` → ドキュメントが削除される。存在しない物件(id=4)の delete イベントを
  流してもエラーにならず正常終了した(合格)
- `record-type: control` → 無視され、エラーも副作用も発生しない(合格)
- 未知の operation が来ても Lambda はクラッシュしない(`build_document` → upsert のパスに
  自然に乗るだけで、例外は起きない設計にした)

## V5. 論理削除がインデックスから落ちるか — **合格**

物件2の `published` を `1→0` に UPDATE し、CDC イベントを流したところ、
Lambda が `build_document` の結果から `published: false` を検知して
ドキュメントを削除し、`_doc/2` が 404 を返すようになった。

## V6. マッピング変更の無停止入れ替え — **合格**

`create-index.sh v1` → `v2` → `v1` と切り替えながら `_alias/properties_search` を
確認したところ、`properties_search` が原子的に張り替わり、検索スクリプトを
`properties_search` に向けたまま(URL変更なしで)新旧インデックスを切り替えられることを確認した。

## V7. フルリインデックスの所要時間 — **記録(閾値なし)**

シードデータを 10,003 件(公開物件、画像・駅各1件ずつ付与)に増やして
`scripts/full-reindex.sh` を計測した。

- 実行時間: 約 7.1 秒 / 10,003 件 → **約 0.71 ms/件**(bulk API 1回、ローカル環境)
- 素朴な外挿: 10万件で約71秒、100万件で約12分程度になる計算(MySQL からの読み出しと
  OpenSearch への bulk 投入がボトルネックにならない前提の単純な線形外挿であり、
  MySQL 側のインデックス設計や OpenSearch のシャード数、ネットワーク遅延次第で
  本番の数値は変わりうる)
- 計測後、ベンチマーク用データは MySQL・OpenSearch 双方から削除し、
  シードデータ3件の状態に戻した

## 検証しなかったこと(ローカルの模倣物では測れないため)

@docs/verification-plan.md の「ローカルでは検証しないこと」に記載の通り、
Aurora の binlog 設定の正しさ、CDC の同期ラグの実測値、DMS タスク停止からの復旧、
OpenSearch Service のノードサイジングは対象外。これらは AWS の検証アカウントで
小さく DMS タスクを1本立てて確認する。

---

## 最終的な結論

### 1. 物件検索の要件は OpenSearch の Query DSL で表現しきれるか

**表現しきれる。** V2 の6要件すべてが単一クエリで意図通りに動いた。
特に「特定路線かつ徒歩N分以内」のような同一駅内での AND 条件は、`nested` 型を
使わない設計だと誤ヒットしうることを反例(4b)で確認できた。これは RDB の
複雑な JOIN + WHERE で書くよりも、`nested` query の方が意図を素直に表現できる一例。

### 2. 複数テーブルの非正規化は Lambda で無理なく書けるか。その保守コストはどの程度か

**無理なく書ける。** `build_document(mysql, property_id)` は40行程度で
properties / property_images / property_stations を1ドキュメントに組み立てられた。
ロジック自体の保守コストは低い。

一方で **保守コストの大半はロジックではなくパッケージング側にある**ことが今回の
最大の発見だった。`mysql2` のようなネイティブ拡張 gem を Lambda(Linux)向けに
ビルドする作業は、Amazon Linux 2 の古い依存関係の衝突(D12)や、ビルド環境と
実行環境の共有ライブラリの差異(`libmysqlclient.so.18` を手動で同梱する必要があった)
など、本質的でない手間が大きかった。本番では Lambda コンテナイメージや
Lambda Layers を使った依存管理を前提にすべきで、この検証で得た
「何を vendoring すればよいか」の知見(D12)がそのまま活きる。

### 3. 結果整合性のラグは業務上許容できる水準か

**ローカルでは判断できない。** CDC 部分(binlog → DMS)を再現していないため、
「INSERT から検索反映までの実際のラグ」は測定対象外(@docs/decisions.md の D4/D5)。
今回測れたのは「Kinesis に put-record してから OpenSearch に反映されるまで」の
Lambda 単体の処理時間で、数秒以内に収まったが、これは DMS の CDC 検知〜Kinesis 配信
までの時間を含まない。AWS の検証アカウントで DMS タスクを1本立てて実測する必要がある。

### 4. そもそも RDB のインデックス最適化では足りないのか(最重要)

**この検証だけでは判断できない。** @docs/decisions.md の D1 に書いた通り、
この検証は「OpenSearch が使えるか」を確かめたものであり、「使うべきか」を
証明するものではない。物件数が数万〜数十万件程度なら適切な複合インデックスや
リードレプリカで RDB のまま捌ける可能性があり、**導入前に本番相当のデータ量で
スロークエリログと DB の CPU/IO 使用率を実測してボトルネックを確認することが必須**。
今回の V7 で「フルリインデックスは1万件あたり約7秒」という参考値は得られたが、
これは「OpenSearch 導入のコスト」の一部であって、「RDB のままでは無理」の証明にはならない。
