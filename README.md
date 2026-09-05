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
Aurora MySQL ──binlog──> DMS(CDC) ──> Kinesis ──> Lambda(非正規化) ──> OpenSearch
                                                                          │
                                            Rails 検索API ────────────────┘
```

ローカルでは DMS 部分を再現せず、DMS 形式のイベントをフィクスチャとして
Kinesis に流す。理由は [docs/decisions.md](docs/decisions.md) の D4 / D5 を参照。

```
[LocalStack Community : 1コンテナ]  OpenSearch + Kinesis + Lambda
[素の Docker]                        MySQL 8.0 (binlog=ROW)
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

./scripts/search-examples.sh              # 各種クエリの動作確認
./scripts/emit-cdc-event.sh insert property_stations 1   # CDC イベントを Kinesis に流す
```

LocalStack はデータを永続化しないため、再起動したら `create-domain.sh` 以降を流し直す
(詳細は [docs/decisions.md](docs/decisions.md) の D11)。

## 注意

- このリポジトリは元々 private 運用の想定だったが、既存の public リポジトリを流用しており、
  ユーザー承認のもと例外的に public のまま運用している
- `.env`、LocalStack の auth token、AWS の認証情報、実データはコミットしない
- LocalStack の DMS / RDS プロバイダは有料プラン限定のため使わない
