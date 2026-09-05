#!/bin/bash
# reference/index-mapping.json でインデックスを作成し、
# エイリアス properties_search を原子的に張り替える。
# 例: ./scripts/create-index.sh v1
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

VERSION="${1:?バージョンを指定してください (例: v1)}"
INDEX_NAME="properties_${VERSION}"
ALIAS_NAME="properties_search"

echo "インデックス ${INDEX_NAME} を作成します..."
CREATE_RESPONSE=$(curl -s -XPUT "${OS_ENDPOINT}/${INDEX_NAME}" \
  -H 'Content-Type: application/json' \
  -d @reference/index-mapping.json)
echo "$CREATE_RESPONSE"

# curl は HTTP 4xx/5xx でも exit 0 を返すため、レスポンス本体で成否を判定する
# (already_exists は再実行時によくあるので許容し、それ以外のエラーで止める)
if echo "$CREATE_RESPONSE" | jq -e 'has("error") and (.error.type != "resource_already_exists_exception")' > /dev/null; then
  echo "インデックス作成に失敗しました: ${CREATE_RESPONSE}" >&2
  exit 1
fi

echo
echo "エイリアス ${ALIAS_NAME} を ${INDEX_NAME} に張り替えます..."

# 既存のエイリアス割り当てを調べ、他のインデックスから外しつつ新インデックスに張る
# (add/remove を1リクエストにまとめることで無停止で切り替わる)
# エイリアス未作成時は 404 の {"error":...} が返るので、その場合は空とみなす
OLD_INDEX=$(curl -s "${OS_ENDPOINT}/_alias/${ALIAS_NAME}" | jq -r 'if has("error") then "" else keys[] end')

ACTIONS='{"actions":[{"add":{"index":"'"${INDEX_NAME}"'","alias":"'"${ALIAS_NAME}"'"}}'
if [ -n "$OLD_INDEX" ] && [ "$OLD_INDEX" != "$INDEX_NAME" ]; then
  for idx in $OLD_INDEX; do
    ACTIONS="${ACTIONS},{\"remove\":{\"index\":\"${idx}\",\"alias\":\"${ALIAS_NAME}\"}}"
  done
fi
ACTIONS="${ACTIONS}]}"

ALIAS_RESPONSE=$(curl -s -XPOST "${OS_ENDPOINT}/_aliases" \
  -H 'Content-Type: application/json' \
  -d "$ACTIONS")
echo "$ALIAS_RESPONSE"

if echo "$ALIAS_RESPONSE" | jq -e 'has("error")' > /dev/null; then
  echo "エイリアスの張り替えに失敗しました: ${ALIAS_RESPONSE}" >&2
  exit 1
fi

echo
echo "完了: ${ALIAS_NAME} -> ${INDEX_NAME}"
