# property-search-lab

物件検索を OpenSearch に逃がす構成の技術検証リポジトリ。

Rails + Aurora MySQL のアプリで物件検索がパフォーマンスのボトルネックになる場合に、
OpenSearch への分離が有効かを判断するための材料を集める。
**プロダクションコードではなく、技術選定の判断根拠を得るための実験場。**

## ドキュメント

| ファイル | 内容 |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Claude Code 用のプロジェクト方針。毎セッション読まれる |
| [TASKS.md](TASKS.md) | 実装タスクの分解。Task 0 から順に進める |
| [docs/architecture.md](docs/architecture.md) | 本番想定のシステム構成と設計判断 |
| [docs/local-environment.md](docs/local-environment.md) | ローカル検証環境の構成 |
| [docs/verification-plan.md](docs/verification-plan.md) | 検証シナリオと合格基準 |
| [docs/decisions.md](docs/decisions.md) | 却下した案とその理由 |
| [reference/](reference/) | 再利用する成果物(インデックスマッピング、スキーマ) |

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

まだ実装は入っていない。Claude Code に [TASKS.md](TASKS.md) の Task 0 から進めてもらう。

```bash
claude
> TASKS.md の Task 0 から進めて
```

## 注意

- **このリポジトリは private で運用する。** 公開しない
- `.env`、LocalStack の auth token、AWS の認証情報、実データはコミットしない
- LocalStack の DMS / RDS プロバイダは有料プラン限定のため使わない
