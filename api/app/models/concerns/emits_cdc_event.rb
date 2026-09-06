module EmitsCdcEvent
  extend ActiveSupport::Concern

  # included do ブロックの実行時 self は include 先(ActiveRecord::Base 継承クラス)になるが、
  # Steep は ActiveSupport::Concern のこの動的な self 差し替えまでは追えないため、
  # 以下は "singleton(EmitsCdcEvent) にそのメソッドがない" という誤検知になる
  included do
    after_create_commit { emit_cdc_event("insert") } # steep:ignore
    after_update_commit { emit_cdc_event("update") } # steep:ignore
    after_destroy_commit { emit_cdc_event("delete") } # steep:ignore
  end

  private

  #: (String) -> void
  def emit_cdc_event(operation)
    Cdc.publish(table: self.class.table_name, operation: operation, data: cdc_attributes) # steep:ignore
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    # Kinesis 側の問題でアプリの書き込み自体を失敗させない(本番の DMS も非同期で疎結合)
    Rails.logger.error("[CDC] put-record failed: #{e.class}: #{e.message}")
  end

  # attributes は include 先の ActiveRecord::Base インスタンスメソッド(理由は上記コメント参照)
  #: () -> Hash[String, untyped]
  def cdc_attributes
    attributes.transform_values do |value| # steep:ignore
      case value
      when Time, ActiveSupport::TimeWithZone then value.utc.strftime("%Y-%m-%d %H:%M:%S")
      when BigDecimal then value.to_f
      else value
      end
    end
  end
end
