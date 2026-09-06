# DMS 形式(data/metadata)の CDC イベントエンベロープを組み立てる。
# scripts/emit-cdc-event.rb と Rails(api/)の両方から共通で使う唯一の実装にする
# (形式を2箇所に分散させると @docs/decisions.md D5 の制約からドリフトする)。

def build_dms_event(table:, operation:, data:)
  {
    "data" => data,
    "metadata" => {
      "timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ"),
      "record-type" => "data",
      "operation" => operation,
      "partition-key-type" => "schema-table",
      "schema-name" => "property_dev",
      "table-name" => table
    }
  }
end
