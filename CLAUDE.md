# property-search-lab

物件検索を OpenSearch に逃がす構成の技術検証リポジトリ。個人の検証用で、プロダクションコードではない。

## このリポジトリの目的

Rails + Aurora MySQL のアプリで、物件検索のパフォーマンスを OpenSearch で解決できるかを判断するための材料を集める。
**動くものを作ることではなく、技術選定の判断根拠を得ることがゴール。**

詳細は以下を参照。必要になった時点で読むこと。

- @docs/architecture.md — 本番想定のシステム構成と設計判断
- @docs/local-environment.md — ローカル検証環境の構成
- @docs/verification-plan.md — 検証シナリオと合格基準
- @docs/decisions.md — なぜこの構成にしたかの決定記録
- @docs/results.md — 検証結果と最終的な結論

## 技術スタック

- ローカル環境: Docker Compose + LocalStack Community
- OpenSearch: LocalStack の OpenSearch プロバイダ(kuromoji 同梱)
- MySQL: 素の MySQL 8.0 コンテナ(binlog ROW 有効)
- Lambda: LocalStack の Lambda(Ruby ランタイム)
- API: `api/` の Rails 8(`--api` モード)。登録・検索のインターフェースとして使う。
  ホストで `bin/rails s` を直接起動する(docker-compose には加えない)。
  スキーマは reference/schema.sql が正でマイグレーションは持たない
- 検索クライアント: Ruby + `opensearch-ruby`(scripts/ と api/ の双方で使用)
- IaC: 使わない。シェルスクリプト + AWS CLI で完結させる

## 守ってほしいこと

- **LocalStack の有料機能を使う実装を提案しない。** DMS / RDS プロバイダは有料プラン限定。Community で完結する構成を維持する
- **Kinesis に流すイベントは AWS DMS の形式に合わせる。** `{"data": {...}, "metadata": {...}}` 形式。Debezium の `before`/`after` 形式にしない。理由は @docs/decisions.md
- OpenSearch のインデックス名はコードに直接書かず、エイリアス `properties_search` を経由する
- ドキュメントの `_id` は必ず MySQL の主キーと一致させる
- 検証用のコードなので、過剰な抽象化やレイヤリングをしない。1ファイルで読み切れる粒度を保つ
- コメントは「なぜそうしたか」を書く。「何をしているか」は書かない
- 日本語でコミットメッセージとコメントを書く

## やらないこと

- 本番相当の認証・認可・IAM 設定(ローカルは security plugin 無効で進める)
- CI/CD の構築

## Git 運用

- リモートは GitHub の `property-search-lab` リポジトリ。既存の public リポジトリを流用しており、
  ユーザー承認のもと例外的に public のまま運用している(本来は private が原則)
- 検証の性質上コミットは細かくてよいが、1コミット1話題にする
- LocalStack の auth token や AWS の認証情報を絶対にコミットしない。`.env` は必ず `.gitignore` に入れる
