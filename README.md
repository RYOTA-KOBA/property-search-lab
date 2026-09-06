# property-search-lab

物件検索を OpenSearch に逃がす構成の技術検証リポジトリ。

Rails + Aurora MySQL のアプリで物件検索がパフォーマンスのボトルネックになる場合に、
OpenSearch への分離が有効かを判断するための材料を集める。
**プロダクションコードではなく、技術選定の判断根拠を得るための実験場。**

## ドキュメント

| ファイル | 内容 |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Claude Code 用のプロジェクト方針。毎セッション読まれる |
| [docs/architecture.md](docs/architecture.md) | 本番想定のシステム構成と設計判断 |
| [docs/local-environment.md](docs/local-environment.md) | ローカル検証環境の構成 |
| [docs/verification-plan.md](docs/verification-plan.md) | 検証シナリオと合格基準 |
| [docs/decisions.md](docs/decisions.md) | 却下した案とその理由、環境構築で踏んだ問題の記録 |
| [docs/results.md](docs/results.md) | 検証結果と最終的な結論 |
| [reference/](reference/) | 再利用する成果物(インデックスマッピング、スキーマ、DMS イベントサンプル) |

## 構成の要約

```
[登録]  Client ──> Rails(api/) ──> MySQL(正のデータストア)
                        │ after_commit(本番の DMS の代役)
                        v
                     Kinesis ──> Lambda(非正規化) ──> OpenSearch
                                                            │
[検索]  Client ──> Rails(api/) ──> OpenSearch ─────────────┘
        Client ──> Rails(api/) ──> MySQL(詳細1件、CDC ラグの影響を受けない)
```

ローカルでは DMS(binlog の検知)部分を再現せず、Rails の `after_commit` が
その代役を務める。理由は [docs/decisions.md](docs/decisions.md) の D4 / D5 / D14 を参照。

```
[LocalStack Community : 1コンテナ]  OpenSearch + Kinesis + Lambda + Logs
[素の Docker]                        MySQL 8.0 (binlog=ROW)
[ホストで直接起動]                    Rails API(api/)
```

## はじめかた

```bash
cp .env.example .env
# .env に LOCALSTACK_AUTH_TOKEN(app.localstack.cloud で無料登録して取得)を設定

docker compose up -d
./scripts/setup-mysql.sh        # スキーマ + シードデータ投入
./scripts/create-domain.sh      # OpenSearch ドメイン作成
./scripts/create-index.sh v1    # インデックス作成 + エイリアス張り替え
./scripts/full-reindex.sh       # MySQL から全件を非正規化して投入
./scripts/deploy-lambda.sh      # Lambda 作成 + Kinesis イベントソースマッピング

./scripts/tail-cdc.sh &          # CDC ログを別端末(または & )で追尾しておく
(cd api && bundle install && bin/rails s)   # 登録・検索用の API を起動

curl -XPOST localhost:3000/properties -H 'Content-Type: application/json' -d '{
  "property": {"name": "王子テラス", "address": "東京都北区王子1-1-1",
    "price": 90000, "layout": "1LDK", "area_m2": 30,
    "property_stations_attributes": [{"station_name": "王子", "line_name": "JR京浜東北線", "walk_minutes": 4}]}
}'
curl "localhost:3000/properties/search?q=王子"

./scripts/search-examples.sh              # scripts 側からもクエリを確認できる
./scripts/emit-cdc-event.sh insert property_stations 1   # SQL を直接いじった場合の手動送出
```

LocalStack はデータを永続化しないため、再起動したら `create-domain.sh` 以降を流し直す
(詳細は [docs/decisions.md](docs/decisions.md) の D11)。

## 注意

- LocalStack の DMS / RDS プロバイダは有料プラン限定のため使わない
