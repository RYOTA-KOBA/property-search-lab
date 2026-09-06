class Property < ApplicationRecord
  include EmitsCdcEvent

  has_many :property_images, -> { order(:position) }, dependent: :destroy
  has_many :property_stations, dependent: :destroy

  accepts_nested_attributes_for :property_images, :property_stations

  # BigDecimal は as_json でデフォルト文字列化されるが、OpenSearch 側(検索 API)は
  # 数値で返るため、詳細 API と型を揃える
  #: (?Hash[untyped, untyped] options) -> Hash[String, untyped]
  def as_json(options = {})
    super.merge("area_m2" => area_m2&.to_f, "lat" => lat&.to_f, "lng" => lng&.to_f)
  end
end
