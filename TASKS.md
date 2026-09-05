# 実装タスク

上から順に進める。各タスクは独立してコミットできる粒度にしてある。
セッションを跨ぐときは完了したタスクにチェックを入れること。

---

## Task 0: GitHub プライベートリポジトリの作成と初回 push

**このタスクを最初に完了させる。** 以降の作業はすべてこのリポジトリ上で行う。

- [x] `gh` CLI が使えるか確認する(`gh auth status`)
- [x] `property-search-lab` リポジトリを使う
      (既に GitHub 上に存在していたため作成はスキップ。**public のままで進める運用とすることをユーザーが承認済み**。
      理由: リポジトリ名は既存のものを流用し、内容自体に機密情報がないため)
- [x] `.gitignore` を作成する。最低限以下を含める
      - `.env`
      - `*.log`
      - `tmp/`
      - `vendor/bundle/`
      - `**/lambda.zip`
- [x] 現在のドキュメント一式を初回コミットして push する

**注意**

- リポジトリは**必ず private** にする。公開リポジトリにしない
- LocalStack の auth token、AWS の認証情報、社内の実データを絶対にコミットしない
- 名前が既に使われている場合は `opensearch-cdc-lab` を代替候補とする(ユーザーに確認すること)

---

## Task 1: ローカル環境の起動

- [x] `docker-compose.yml` を作成する
      - LocalStack(`localstack/localstack`)、`SERVICES=opensearch,kinesis,lambda,secretsmanager`
      - MySQL 8.0(binlog 設定は `mysql/conf.d/binlog.cnf` で与える)
- [x] `mysql/conf.d/binlog.cnf` を作成する
      - `binlog_format=ROW`, `binlog_row_image=FULL`, `server-id`, `log_bin`
      - 本番の Aurora パラメータグループと対応する旨をコメントで書く
- [x] `.env.example` を作成する
- [x] `docker compose up -d` で両方が healthy になることを確認する

**確認**: `curl http://localhost:4566/_localstack/health` で opensearch / kinesis / lambda が `available` — 確認済み

**追記(2026-09-06)**: LocalStack は 2026-03 の Community/Pro イメージ統合以降、
無料アカウントの `LOCALSTACK_AUTH_TOKEN` がないと起動しなくなった(有料機能の利用ではない)。
`.env` に設定して起動する運用に変更(この運用自体は @CLAUDE.md の git 運用セクションで元々想定されていた)。

---

## Task 2: MySQL スキーマとシードデータ

- [x] `mysql/init/01_schema.sql` を作成する。スキーマは @reference/schema.sql をそのまま使う
- [x] `scripts/setup-mysql.sh` を作成する(初期化 + シード投入)
- [x] シードデータは非正規化の検証ができるよう、1物件に複数の画像と複数の駅を持たせる — 確認済み(物件1: 画像2件/駅2件)

---

## Task 3: OpenSearch ドメインとインデックス

- [x] `scripts/create-domain.sh` — LocalStack に OpenSearch ドメインを作成し、
      払い出されたエンドポイントを `.env` に書き出す
- [x] `scripts/create-index.sh <version>` — @reference/index-mapping.json でインデックスを作成し、
      エイリアス `properties_search` を原子的に張り替える
- [x] kuromoji が利用可能なことを `_analyze` API で確認する

**確認**: @docs/verification-plan.md の V1 が通る(icu_normalizer 部分は対象外。D10 参照) — 確認済み

---

## Task 4: 非正規化ロジックとフルリインデックス

- [ ] `lib/document_builder.rb` — `build_document(property_id)` を実装する。
      MySQL から properties / property_images / property_stations を引いて
      1つの検索ドキュメントに組み立てる
      - **この関数が本番の Lambda にそのまま移植できる中核部分**。他の関心事を混ぜないこと
- [ ] `scripts/full-reindex.rb` — 全件を bulk API で投入する。`[index_name]` を引数で受ける
- [ ] `scripts/full-reindex.sh` — 上記のラッパー

**確認**: 全件投入後、ドキュメント数がシードデータの公開物件数と一致する

---

## Task 5: 検索クエリの検証

- [ ] `scripts/search-examples.sh` — @docs/verification-plan.md の V2 の6要件を
      それぞれ curl で叩けるようにする
- [ ] 各クエリの意図をコメントで書く(なぜ `filter` に入れたか、など)

**確認**: V2 の6件すべてが意図した結果を返す

---

## Task 6: DMS イベントのフィクスチャ

- [ ] `reference/dms-event-samples/` に insert / update / delete / control の
      4種類の DMS 形式イベント JSON を作る
      - 形式は `{"data": {...}, "metadata": {"operation": "...", "record-type": "...", ...}}`
      - **Debezium 形式にしないこと**。理由は @docs/decisions.md の D5
- [ ] `scripts/emit-cdc-event.sh <operation> <table> <id>` —
      MySQL の現在値を読んで DMS 形式イベントを組み立て、Kinesis に put-record する

---

## Task 7: Lambda の実装とデプロイ

- [ ] `lambda/handler.rb` — Kinesis イベントを受け取り、
      DMS のエンベロープをパースして対象 property_id を割り出し、
      `build_document` で非正規化して OpenSearch に upsert する
      - `properties` テーブルのイベントは `data.id`、子テーブルのイベントは `data.property_id` を見る
      - `operation` が `delete`、または `published` が false のときはドキュメントを削除する
      - `record-type` が `control` のイベントは無視する
- [ ] `scripts/deploy-lambda.sh` — zip 化して LocalStack に関数を作成し、
      Kinesis のイベントソースマッピングを設定する

**確認**: @docs/verification-plan.md の V3 / V4 / V5 が通る

---

## Task 8: 検証結果の記録

- [ ] `docs/results.md` を作成し、V1〜V7 の結果を記録する
- [ ] 各シナリオについて「合格 / 不合格 / 保留」と、判断に至った観測値を書く
- [ ] 最後に @docs/verification-plan.md の「最終的に出したい結論」の4問に答える

---

## 補足: 進め方の注意

- **一度に全部作らない。** Task 単位で動かして確認し、コミットしてから次に進む
- 詰まったら実装を進める前に、何が分からないかをユーザーに聞く
- @CLAUDE.md の「守ってほしいこと」を逸脱する提案が必要になった場合は、
  勝手に進めずユーザーに確認する
