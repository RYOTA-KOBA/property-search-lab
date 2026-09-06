class Property < ApplicationRecord
  include EmitsCdcEvent

  has_many :property_images, -> { order(:position) }, dependent: :destroy
  has_many :property_stations, dependent: :destroy

  accepts_nested_attributes_for :property_images, :property_stations
end
