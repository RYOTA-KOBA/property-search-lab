#!/bin/bash
# docker-entrypoint-initdb.d は初回起動(空ボリューム)時しか走らないため、
# 起動済みのコンテナに対してスキーマ適用とシード投入をやり直したい場合はこのスクリプトを使う。
# スキーマの正は api/db/Schemafile(Ridgepole)。reference/schema.sql は廃止した(docs/decisions.md D15)。
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

echo "MySQL の起動を待機しています..."
until docker compose exec -T mysql mysqladmin ping -h localhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do
  sleep 1
done

echo "テスト用データベース(property_test)を用意します..."
# property_dev は MYSQL_DATABASE 環境変数でコンテナ起動時に自動作成されるが、
# property_test は対象外なのでここで作成し、app ユーザーに権限を付与する
docker compose exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
  CREATE DATABASE IF NOT EXISTS property_test CHARACTER SET utf8mb4;
  GRANT ALL PRIVILEGES ON property_test.* TO '$MYSQL_USER'@'%';
  FLUSH PRIVILEGES;
"

echo "Ridgepole でスキーマを適用します(development / test)..."
# 同一 rake 呼び出しに ridgepole:apply[development] ridgepole:apply[test] を並べると、
# Rake は同じタスクの2回目の invoke を(引数が違っても)無視するため、プロセスを分けて実行する
(cd api && MYSQL_HOST=127.0.0.1 bundle exec rake "ridgepole:apply[development]")
(cd api && MYSQL_HOST=127.0.0.1 bundle exec rake "ridgepole:apply[test]")

echo "シードデータを投入します..."
(cd api && MYSQL_HOST=127.0.0.1 bin/rails db:seed)

echo "完了"
