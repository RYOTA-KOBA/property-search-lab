require "rails_helper"

RSpec.describe PropertyStation do
  it "property に属する" do
    property = Property.create!(name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK")
    station = property.property_stations.create!(station_name: "王子神谷", walk_minutes: 6)

    expect(station.property).to eq(property)
  end
end
