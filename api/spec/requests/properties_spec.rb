require "rails_helper"

RSpec.describe "Properties", type: :request do
  describe "POST /properties" do
    it "物件と紐づく画像・駅を作成して 201 を返す" do
      post "/properties", params: {
        property: {
          name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK",
          property_images_attributes: [{ url: "https://example.com/a.jpg", position: 0 }],
          property_stations_attributes: [{ station_name: "王子", walk_minutes: 5 }]
        }
      }

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("テスト物件")
      expect(body["property_images"].size).to eq(1)
      expect(body["property_stations"].size).to eq(1)
    end
  end

  describe "GET /properties/:id" do
    it "物件を返す" do
      property = Property.create!(name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK")

      get "/properties/#{property.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(property.id)
    end

    it "存在しない場合は 404 を返す" do
      get "/properties/999999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /properties/:id" do
    it "物件を更新する" do
      property = Property.create!(name: "テスト物件", address: "東京都北区1-1-1", price: 90_000, layout: "1LDK")

      patch "/properties/#{property.id}", params: { property: { price: 100_000 } }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["price"]).to eq(100_000)
    end
  end

  describe "GET /properties/search" do
    it "OpenSearch の検索結果を整形して返す" do
      fake_response = {
        "hits" => {
          "total" => { "value" => 1 },
          "hits" => [{ "_source" => { "id" => 1, "name" => "テスト物件" } }]
        }
      }
      allow(OpenSearch::Client).to receive(:new).and_return(double("opensearch_client", search: fake_response))

      get "/properties/search", params: { q: "テスト" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "total" => 1, "properties" => [{ "id" => 1, "name" => "テスト物件" }]
      )
    end
  end
end
