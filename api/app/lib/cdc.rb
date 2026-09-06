# after_commit から DMS 形式イベントを Kinesis に put-record する。
# 本番の DMS(binlog CDC)の代役であり、docs/decisions.md D3 で却下した
# 「after_commit での同期更新」とは狙いが異なる(検索インデックス更新の同期化ではなく、
# ローカルで再現していない DMS のトリガー役を Rails に肩代わりさせているだけ)
require "aws-sdk-kinesis"

module Cdc
  STREAM_NAME = "property-cdc-events"

  #: () -> untyped
  def self.client
    @client ||= Aws::Kinesis::Client.new(
      endpoint: ENV.fetch("LOCALSTACK_ENDPOINT", "http://localhost:4566"),
      region: ENV.fetch("AWS_DEFAULT_REGION", "ap-northeast-1"),
      access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test"),
      # test 環境では LocalStack に依存させず、AWS SDK 組み込みのスタブで完結させる
      stub_responses: Rails.env.test?
    ).tap { |c| ensure_stream(c) }
  end

  #: (untyped) -> void
  def self.ensure_stream(client)
    client.create_stream(stream_name: STREAM_NAME, shard_count: 1)
  rescue Aws::Kinesis::Errors::ResourceInUseException
    # 既に存在する
  end

  #: (table: String, operation: String, data: Hash[String, untyped]) -> Hash[String, untyped]
  def self.publish(table:, operation:, data:)
    event = build_dms_event(table: table, operation: operation, data: data)
    client.put_record(
      stream_name: STREAM_NAME,
      partition_key: "#{table}-#{data['id']}",
      data: JSON.generate(event)
    )
    Rails.logger.info("[CDC] table=#{table} operation=#{operation} id=#{data['id']} put-record stream=#{STREAM_NAME}")
    event
  end
end
