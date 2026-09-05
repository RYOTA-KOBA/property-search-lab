#!/bin/bash
# mysql/init/01_schema.sql をコンテナに流し込んでスキーマとシードデータを投入する。
# docker-entrypoint-initdb.d は初回起動(空ボリューム)時しか走らないため、
# 既に起動済みのコンテナに対して再投入したい場合はこのスクリプトを使う。
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

echo "MySQL の起動を待機しています..."
until docker compose exec -T mysql mysqladmin ping -h localhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do
  sleep 1
done

echo "スキーマとシードデータを投入します..."
docker compose exec -T mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < mysql/init/01_schema.sql

echo "完了"
