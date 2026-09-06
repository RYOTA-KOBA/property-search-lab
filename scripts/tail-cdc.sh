#!/bin/bash
# Lambda(property-document-sync)の CloudWatch Logs を追尾表示する。
# LocalStack では `aws logs tail --follow` が反応しなかったため、
# filter-log-events を定期実行するポーリング方式にしている。
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
ENDPOINT_URL="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
LOG_GROUP="/aws/lambda/property-document-sync"

echo "CDC ログを追尾します(${LOG_GROUP})... Ctrl+C で終了"

start_time=$(($(date +%s) * 1000))

while true; do
  end_time=$(($(date +%s) * 1000))

  aws --endpoint-url "$ENDPOINT_URL" logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --query 'events[].message' \
    --output text 2>/dev/null | grep '\[CDC\]' || true

  start_time=$end_time
  sleep 2
done
