#!/bin/bash
# properties_search に対して任意の Query DSL を投げる。
# 使い方: ./scripts/query.sh '{"query": {"prefix": {"name": "ハイ"}}}'
#         echo '{"query": {"match_all": {}}}' | ./scripts/query.sh
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

if [ $# -ge 1 ]; then
  BODY="$1"
else
  BODY="$(cat)"
fi

curl -s -XPOST "${OS_ENDPOINT}/properties_search/_search" \
  -H 'Content-Type: application/json' \
  -d "$BODY" | jq .
