# DMS(Kinesis 経由)の CDC イベントを受け取り、対象物件を非正規化して OpenSearch に反映する。
# lib/document_builder.rb はビルド時にこのディレクトリへコピーされたものを使う(deploy-lambda.sh 参照)。
require "bundler/setup" # vendor/bundle に固めた gem を読めるようにする
require "json"
require "base64"
require "mysql2"
require "opensearch-ruby"
require_relative "lib/document_builder"

def lambda_handler(event:, context:)
  mysql = mysql_client
  client = opensearch_client

  event.fetch("Records", []).each do |record|
    process_record(record, mysql, client)
  end

  { statusCode: 200 }
end

def process_record(record, mysql, client)
  payload = JSON.parse(Base64.decode64(record.dig("kinesis", "data")))
  metadata = payload["metadata"] || {}

  # テーブル作成通知などの control イベントには対象データが無いので無視する
  return if metadata["record-type"] == "control"

  table = metadata["table-name"]
  operation = metadata["operation"]
  data = payload["data"] || {}

  # properties 自身のイベントは id、子テーブル(images/stations)のイベントは
  # property_id で「どの物件のドキュメントを更新すべきか」を割り出す
  property_id = table == "properties" ? data["id"] : data["property_id"]
  return if property_id.nil?

  index_name = "properties_search"

  # delete は子テーブルの1行削除でも物件ドキュメント全体を削除する。
  # 「残り行から再構築する」までは検証の要件外なので単純化している
  if operation == "delete"
    delete_document(client, index_name, property_id)
    return
  end

  doc = build_document(mysql, property_id)
  if doc.nil? || !doc[:published]
    delete_document(client, index_name, property_id)
  else
    client.index(index: index_name, id: property_id, body: doc)
  end
end

def delete_document(client, index_name, id)
  client.delete(index: index_name, id: id)
rescue OpenSearch::Transport::Transport::Errors::NotFound
  # delete イベントの重複配信・リトライで既に存在しない場合は何もしない
end

def mysql_client
  Mysql2::Client.new(
    host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
    username: ENV.fetch("MYSQL_USER"),
    password: ENV.fetch("MYSQL_PASSWORD"),
    database: ENV.fetch("MYSQL_DATABASE"),
    encoding: "utf8mb4"
  )
end

def opensearch_client
  OpenSearch::Client.new(host: ENV.fetch("OS_ENDPOINT"))
end
