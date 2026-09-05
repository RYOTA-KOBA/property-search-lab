#!/usr/bin/env ruby
# 全件を MySQL から読み直して OpenSearch に bulk 投入する。
# 公開中の物件だけを検索対象にするため published=0 の物件は最初から対象外にする。
require "dotenv/load"
require "mysql2"
require "opensearch-ruby"
require_relative "../lib/document_builder"

index_name = ARGV[0] || "properties_search"

mysql = Mysql2::Client.new(
  host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
  username: ENV.fetch("MYSQL_USER"),
  password: ENV.fetch("MYSQL_PASSWORD"),
  database: ENV.fetch("MYSQL_DATABASE"),
  encoding: "utf8mb4"
)

client = OpenSearch::Client.new(host: ENV.fetch("OS_ENDPOINT"))

property_ids = mysql.query("SELECT id FROM properties WHERE published = 1").map { |row| row["id"] }

if property_ids.empty?
  puts "投入対象の物件がありません"
  exit 0
end

body = property_ids.flat_map do |id|
  doc = build_document(mysql, id)
  [{ index: { _index: index_name, _id: doc[:id] } }, doc]
end

response = client.bulk(body: body)
errors = response["items"].select { |item| item.values.first["error"] }

if errors.any?
  warn "エラーが発生しました: #{errors}"
  exit 1
end

puts "#{property_ids.size} 件を #{index_name} に投入しました"
