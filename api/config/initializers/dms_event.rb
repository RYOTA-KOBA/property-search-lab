# build_dms_event はリポジトリ直下の lib/dms_event.rb が唯一の実装で、
# scripts/emit-cdc-event.rb と共有している(docs/decisions.md D5 の形式ドリフト防止)
require_relative "../../../lib/dms_event"
