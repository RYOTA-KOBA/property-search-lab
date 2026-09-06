require "rails_helper"

RSpec.describe PropertyImage do
  it "property に属する" do
    property = Property.create!(name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK")
    image = property.property_images.create!(url: "https://example.com/a.jpg")

    expect(image.property).to eq(property)
  end
end
