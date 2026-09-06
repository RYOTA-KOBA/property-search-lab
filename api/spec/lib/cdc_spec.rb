require "rails_helper"

RSpec.describe Cdc do
  it "DMS 形式(data/metadata)のイベントを Kinesis に put-record する" do
    data = { "id" => 1, "name" => "テスト物件" }

    expect(Cdc.client).to receive(:put_record).with(
      stream_name: Cdc::STREAM_NAME,
      partition_key: "properties-1",
      data: kind_of(String)
    ).and_call_original

    event = Cdc.publish(table: "properties", operation: "insert", data: data)

    expect(event["data"]).to eq(data)
    expect(event["metadata"]["operation"]).to eq("insert")
    expect(event["metadata"]["table-name"]).to eq("properties")
    expect(event["metadata"]["record-type"]).to eq("data")
  end
end
