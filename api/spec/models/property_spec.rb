require "rails_helper"

RSpec.describe Property do
  def build_property(**attrs)
    Property.new({ name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK" }.merge(attrs))
  end

  describe "アソシエーション" do
    it "property_images を position 順に保持する" do
      property = build_property.tap(&:save!)
      property.property_images.create!(url: "https://example.com/b.jpg", position: 1)
      property.property_images.create!(url: "https://example.com/a.jpg", position: 0)

      expect(property.reload.property_images.map(&:url)).to eq(
        ["https://example.com/a.jpg", "https://example.com/b.jpg"]
      )
    end

    it "破棄すると property_images / property_stations も破棄される" do
      property = build_property.tap(&:save!)
      property.property_images.create!(url: "https://example.com/a.jpg")
      property.property_stations.create!(station_name: "王子", walk_minutes: 5)

      expect { property.destroy! }
        .to change(PropertyImage, :count).by(-1)
        .and change(PropertyStation, :count).by(-1)
    end
  end

  describe "#as_json" do
    it "area_m2 / lat / lng を Float にして返す(OpenSearch 側のレスポンスと型を揃えるため)" do
      property = build_property(area_m2: "38.2", lat: "35.769", lng: "139.737").tap(&:save!)

      json = property.as_json

      expect(json["area_m2"]).to eq(38.2)
      expect(json["lat"]).to eq(35.769)
      expect(json["lng"]).to eq(139.737)
    end
  end

  describe "CDC イベント発火(EmitsCdcEvent)" do
    it "create すると Cdc.publish が insert operation で呼ばれる" do
      expect(Cdc).to receive(:publish).with(hash_including(table: "properties", operation: "insert"))

      build_property.save!
    end

    it "update すると Cdc.publish が update operation で呼ばれる" do
      property = build_property.tap(&:save!)

      expect(Cdc).to receive(:publish).with(hash_including(table: "properties", operation: "update"))

      property.update!(price: 100_000)
    end

    it "destroy すると Cdc.publish が delete operation で呼ばれる" do
      property = build_property.tap(&:save!)

      expect(Cdc).to receive(:publish).with(hash_including(table: "properties", operation: "delete"))

      property.destroy!
    end
  end
end
