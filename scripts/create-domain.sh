#!/bin/bash
# LocalStack に OpenSearch ドメインを作成し、払い出されたエンドポイントを .env に書き出す
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
ENDPOINT_URL="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
DOMAIN_NAME="properties"

echo "OpenSearch ドメインを作成します..."
aws --endpoint-url "$ENDPOINT_URL" opensearch create-domain \
  --domain-name "$DOMAIN_NAME" \
  --engine-version "OpenSearch_2.11" \
  > /dev/null

echo "ドメインの起動を待機しています..."
until aws --endpoint-url "$ENDPOINT_URL" opensearch describe-domain --domain-name "$DOMAIN_NAME" \
  --query 'DomainStatus.Processing' --output text | grep -qx "False"; do
  sleep 2
done

DOMAIN_ENDPOINT=$(aws --endpoint-url "$ENDPOINT_URL" opensearch describe-domain --domain-name "$DOMAIN_NAME" \
  --query 'DomainStatus.Endpoint' --output text)
OS_ENDPOINT="http://${DOMAIN_ENDPOINT}"
echo "OpenSearch エンドポイント: $OS_ENDPOINT"

if grep -q '^OS_ENDPOINT=' .env; then
  sed -i.bak "s|^OS_ENDPOINT=.*|OS_ENDPOINT=${OS_ENDPOINT}|" .env && rm .env.bak
else
  echo "OS_ENDPOINT=${OS_ENDPOINT}" >> .env
fi

echo "完了"
