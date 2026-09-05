# ローカル検証環境

## 構成

LocalStack Community(無料)と素の MySQL コンテナを組み合わせるハイブリッド構成。

```
[LocalStack Community : 1コンテナ]
    OpenSearch  +  Kinesis  +  Lambda  +  Secrets Manager
[素の Docker]
    MySQL 8.0 (binlog=ROW)
[ローカル実行]
    検索クエリ確認用 Ruby スクリプト / フルリインデックススクリプト
```

## 本番との対応関係

| 本番 (AWS) | ローカル | 検証できること |
|---|---|---|
| Aurora MySQL | MySQL 8.0 コンテナ | スキーマ設計、binlog 前提条件 |
| DMS レプリケーションインスタンス | **再現しない**(イベントを手で流す) | — |
| Kinesis Data Streams | LocalStack Kinesis | ストリーム経由の配送 |
| Lambda(非正規化) | LocalStack Lambda | **非正規化ロジックとイベントパース** |
| Amazon OpenSearch Service | LocalStack OpenSearch | マッピング、Query DSL、エイリアス運用 |
| Sidekiq 定期ジョブ | ローカル Ruby スクリプト | 全件再投入 |

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

./scripts/setup-mysql.sh        # スキーマ + シードデータ投入
./scripts/create-index.sh v1    # インデックス作成 + エイリアス張り替え
./scripts/deploy-lambda.sh      # Lambda 作成 + Kinesis イベントソースマッピング
./scripts/full-reindex.sh       # MySQL から全件を非正規化して投入

./scripts/search-examples.sh    # 各種クエリの動作確認
./scripts/emit-cdc-event.sh update 1   # DMS形式イベントを Kinesis に流す
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
