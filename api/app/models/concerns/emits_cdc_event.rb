module EmitsCdcEvent
  extend ActiveSupport::Concern

  included do
    after_create_commit { emit_cdc_event("insert") }
    after_update_commit { emit_cdc_event("update") }
    after_destroy_commit { emit_cdc_event("delete") }
  end

  private

  def emit_cdc_event(operation)
    Cdc.publish(table: self.class.table_name, operation: operation, data: cdc_attributes)
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    # Kinesis 側の問題でアプリの書き込み自体を失敗させない(本番の DMS も非同期で疎結合)
    Rails.logger.error("[CDC] put-record failed: #{e.class}: #{e.message}")
  end

  def cdc_attributes
    attributes.transform_values do |value|
      case value
      when Time, ActiveSupport::TimeWithZone then value.utc.strftime("%Y-%m-%d %H:%M:%S")
      when BigDecimal then value.to_f
      else value
      end
    end
  end
end
