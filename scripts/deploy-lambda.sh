#!/bin/bash
# mysql2 はネイティブ拡張の gem で、macOS でビルドしたものは Lambda(Linux)では動かない。
# 実行環境と同じベースイメージ内でビルドし、リンクされる libmysqlclient.so.18 も
# 実行環境にはプリインストールされていないため zip に同梱して LD_LIBRARY_PATH で読ませる。
# 詳細は docs/decisions.md の D12 を参照。
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

FUNCTION_NAME="property-document-sync"
STREAM_NAME="property-cdc-events"
BUILD_IMAGE="public.ecr.aws/lambda/ruby:3.2"
BUILD_DIR="lambda/build"
ENDPOINT_URL="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

echo "ビルドディレクトリを準備します..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/lib"
cp lambda/handler.rb "$BUILD_DIR/"
cp lambda/Gemfile lambda/Gemfile.lock "$BUILD_DIR/"
cp lib/document_builder.rb "$BUILD_DIR/lib/"

echo "Lambda 実行環境と同じイメージ内で mysql2 をビルドします(数分かかります)..."
# --platform を明示しないとホストのネイティブアーキテクチャでビルドされ、
# 下の --architectures arm64 の関数にデプロイした際に実行時ロードエラーになりうる
docker run --rm --platform linux/arm64 --entrypoint /bin/bash -v "$(pwd)/${BUILD_DIR}:/var/task" -w /var/task "$BUILD_IMAGE" -c '
  set -euo pipefail
  yum install -y yum-utils > /dev/null 2>&1
  mkdir -p /tmp/rpms
  yumdownloader --destdir=/tmp/rpms --resolve openssl-devel mariadb-devel gcc make > /dev/null 2>&1
  # openssl-snapsafe-libs と openssl-libs の Conflicts で yum install が通らないため rpm で強制する(D12)
  rpm -Uvh --force --nodeps /tmp/rpms/*.rpm > /dev/null 2>&1

  bundle config set --local path vendor/bundle
  bundle install

  mkdir -p vendor/native
  cp /usr/lib64/mysql/libmysqlclient.so.18 vendor/native/
'

echo "zip を作成します..."
rm -f lambda.zip
(cd "$BUILD_DIR" && zip -r -q ../../lambda.zip .)

echo "Kinesis ストリームの存在を確認します..."
aws --endpoint-url "$ENDPOINT_URL" kinesis create-stream \
  --stream-name "$STREAM_NAME" --shard-count 1 >/dev/null 2>&1 || true

echo "Lambda 関数を作成します..."
ENV_VARS="Variables={OS_ENDPOINT=${OS_ENDPOINT},MYSQL_HOST=mysql,MYSQL_USER=${MYSQL_USER},MYSQL_PASSWORD=${MYSQL_PASSWORD},MYSQL_DATABASE=${MYSQL_DATABASE},LD_LIBRARY_PATH=/var/task/vendor/native,BUNDLE_GEMFILE=/var/task/Gemfile}"

if aws --endpoint-url "$ENDPOINT_URL" lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  aws --endpoint-url "$ENDPOINT_URL" lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file fileb://lambda.zip \
    > /dev/null
  aws --endpoint-url "$ENDPOINT_URL" lambda wait function-updated --function-name "$FUNCTION_NAME"
  aws --endpoint-url "$ENDPOINT_URL" lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "$ENV_VARS" \
    > /dev/null
else
  aws --endpoint-url "$ENDPOINT_URL" lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime ruby3.2 \
    --architectures arm64 \
    --handler handler.lambda_handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://lambda.zip \
    --environment "$ENV_VARS" \
    --timeout 30 \
    > /dev/null
fi

aws --endpoint-url "$ENDPOINT_URL" lambda wait function-active --function-name "$FUNCTION_NAME"

echo "Kinesis のイベントソースマッピングを設定します..."
STREAM_ARN=$(aws --endpoint-url "$ENDPOINT_URL" kinesis describe-stream \
  --stream-name "$STREAM_NAME" --query 'StreamDescription.StreamARN' --output text)

EXISTING_UUID=$(aws --endpoint-url "$ENDPOINT_URL" lambda list-event-source-mappings \
  --function-name "$FUNCTION_NAME" --event-source-arn "$STREAM_ARN" \
  --query 'EventSourceMappings[0].UUID' --output text)

if [ "$EXISTING_UUID" = "None" ] || [ -z "$EXISTING_UUID" ]; then
  aws --endpoint-url "$ENDPOINT_URL" lambda create-event-source-mapping \
    --function-name "$FUNCTION_NAME" \
    --event-source-arn "$STREAM_ARN" \
    --starting-position TRIM_HORIZON \
    --batch-size 1 \
    > /dev/null
  echo "イベントソースマッピングを作成しました"
else
  echo "イベントソースマッピングは既に存在します (UUID=${EXISTING_UUID})"
fi

echo "完了: 関数 ${FUNCTION_NAME} をデプロイし、${STREAM_NAME} に接続しました"
