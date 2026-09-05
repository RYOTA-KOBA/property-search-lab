#!/bin/bash
# MySQL の現在値を読んで DMS 形式(data/metadata)の CDC イベントを組み立て、Kinesis に put-record する。
# 使い方: ./scripts/emit-cdc-event.sh <insert|update|delete> <table> <id>
#
# delete を試す場合は MySQL 側の行を削除する前に呼ぶこと。
# DMS の delete イベントは「削除される直前の行の値」を data として運ぶため、
# 先に行を消してしまうとこのスクリプトが値を読めなくなる。
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

OPERATION="${1:?operation (insert|update|delete) を指定してください}"
TABLE="${2:?table を指定してください}"
ID="${3:?id を指定してください}"
STREAM_NAME="property-cdc-events"
ENDPOINT_URL="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

aws --endpoint-url "$ENDPOINT_URL" kinesis create-stream \
  --stream-name "$STREAM_NAME" --shard-count 1 >/dev/null 2>&1 || true

# テーブルごとに列構成が違うので、非正規化ロジック(lib/document_builder.rb)とは別に
# ここでは素朴に列を並べるだけにする(検証用の小さいスクリプトなので抽象化しない)
case "$TABLE" in
  properties)
    JSON_EXPR="JSON_OBJECT('id', id, 'name', name, 'address', address, 'price', price, 'layout', layout, 'area_m2', area_m2, 'lat', lat, 'lng', lng, 'published', published, 'created_at', DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s'), 'updated_at', DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i:%s'))"
    ;;
  property_images)
    JSON_EXPR="JSON_OBJECT('id', id, 'property_id', property_id, 'url', url, 'position', position)"
    ;;
  property_stations)
    JSON_EXPR="JSON_OBJECT('id', id, 'property_id', property_id, 'station_name', station_name, 'line_name', line_name, 'walk_minutes', walk_minutes)"
    ;;
  *)
    echo "未知の table です: $TABLE" >&2
    exit 1
    ;;
esac

DATA_JSON=$(docker compose exec -T mysql mysql --default-character-set=utf8mb4 -N -uapp -papppass property_dev \
  -e "SELECT ${JSON_EXPR} FROM ${TABLE} WHERE id = ${ID};")

if [ -z "$DATA_JSON" ] || [ "$DATA_JSON" = "NULL" ]; then
  echo "id=${ID} の行が ${TABLE} に見つかりません" >&2
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")

EVENT=$(jq -n \
  --argjson data "$DATA_JSON" \
  --arg operation "$OPERATION" \
  --arg table "$TABLE" \
  --arg timestamp "$TIMESTAMP" \
  '{
    data: $data,
    metadata: {
      timestamp: $timestamp,
      "record-type": "data",
      operation: $operation,
      "partition-key-type": "schema-table",
      "schema-name": "property_dev",
      "table-name": $table
    }
  }')

echo "$EVENT" | jq .

aws --endpoint-url "$ENDPOINT_URL" kinesis put-record \
  --stream-name "$STREAM_NAME" \
  --partition-key "${TABLE}-${ID}" \
  --data "$EVENT" \
  --cli-binary-format raw-in-base64-out \
  > /dev/null

echo "Kinesis (stream=${STREAM_NAME}) に put-record しました"
