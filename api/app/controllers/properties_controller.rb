class PropertiesController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  RESPONSE_INCLUDE = { include: %i[property_images property_stations] }.freeze

  before_action :set_property, only: %i[show update]

  def create
    property = Property.new(property_params)
    property.save!
    render json: property.as_json(**RESPONSE_INCLUDE), status: :created
  end

  def show
    render json: @property.as_json(**RESPONSE_INCLUDE)
  end

  def update
    @property.update!(property_params)
    render json: @property.as_json(**RESPONSE_INCLUDE)
  end

  def search
    render json: PropertySearch.new(search_params).call
  end

  private

  def set_property
    @property = Property.includes(:property_images, :property_stations).find(params[:id])
  end

  def property_params
    params.require(:property).permit(
      :name, :address, :price, :layout, :area_m2, :lat, :lng, :published,
      property_images_attributes: %i[url position],
      property_stations_attributes: %i[station_name line_name walk_minutes]
    )
  end

  def search_params
    params.permit(
      :q, :min_price, :max_price, :max_walk_minutes,
      :lat, :lng, :radius_km, :line_name, :sort, :page, :per_page, :facets,
      layouts: []
    )
  end
end
