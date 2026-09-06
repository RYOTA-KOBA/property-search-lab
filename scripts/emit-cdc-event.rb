#!/usr/bin/env ruby
# MySQL の現在値を読んで DMS 形式の CDC イベントを組み立て、Kinesis に put-record する。
# 使い方: emit-cdc-event.rb <insert|update|delete> <table> <id>
# <id> は常に対象テーブル自身の主キーで、property_images/property_stations では property_id ではない。
#
# delete を試す場合は MySQL 側の行を削除する前に呼ぶこと
# (DMS の delete イベントは削除される直前の行の値を運ぶため、先に消すと読めなくなる)
require "dotenv/load"
require "json"
require "bigdecimal"
require "mysql2"
require "aws-sdk-kinesis"
require_relative "../lib/dms_event"

STREAM_NAME = "property-cdc-events"

TABLE_COLUMNS = {
  "properties" => %w[id name address price layout area_m2 lat lng published created_at updated_at],
  "property_images" => %w[id property_id url position],
  "property_stations" => %w[id property_id station_name line_name walk_minutes]
}.freeze

operation, table, id = ARGV
abort "使い方: emit-cdc-event.rb <insert|update|delete> <table> <id>" unless operation && table && id

columns = TABLE_COLUMNS[table]
abort "未知の table です: #{table}" unless columns

mysql = Mysql2::Client.new(
  host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
  username: ENV.fetch("MYSQL_USER"),
  password: ENV.fetch("MYSQL_PASSWORD"),
  database: ENV.fetch("MYSQL_DATABASE"),
  encoding: "utf8mb4",
  database_timezone: :utc
)

row = mysql.query("SELECT #{columns.join(', ')} FROM #{table} WHERE id = #{id.to_i}").first
abort "id=#{id} の行が #{table} に見つかりません" unless row

data = columns.each_with_object({}) do |column, hash|
  value = row[column]
  # mysql2 は DATETIME を Time、DECIMAL を BigDecimal で返すため、
  # そのまま JSON.generate すると指数表記等になり DMS の実際の出力と異なってしまう
  hash[column] = case value
                 when Time then value.strftime("%Y-%m-%d %H:%M:%S")
                 when BigDecimal then value.to_f
                 else value
                 end
end

event = build_dms_event(table: table, operation: operation, data: data)
puts JSON.pretty_generate(event)

kinesis = Aws::Kinesis::Client.new(
  endpoint: ENV.fetch("LOCALSTACK_ENDPOINT", "http://localhost:4566"),
  region: ENV.fetch("AWS_DEFAULT_REGION", "ap-northeast-1"),
  access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
  secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
)

begin
  kinesis.create_stream(stream_name: STREAM_NAME, shard_count: 1)
rescue Aws::Kinesis::Errors::ResourceInUseException
  # 既に存在する場合はそのまま使う
end

kinesis.put_record(
  stream_name: STREAM_NAME,
  partition_key: "#{table}-#{id}",
  data: JSON.generate(event)
)

puts "Kinesis (stream=#{STREAM_NAME}) に put-record しました"
