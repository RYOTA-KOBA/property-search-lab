require "rails_helper"

# docs/verification-plan.md V2 の6要件に対応するリクエストボディが
# 正しく組み立てられることを、注入したダブルクライアントで検証する
RSpec.describe PropertySearch do
  def request_body_for(params, response: { "hits" => { "total" => { "value" => 0 }, "hits" => [] } })
    captured = nil
    client = double("opensearch_client")
    allow(client).to receive(:search) do |index:, body:|
      captured = body
      response
    end

    PropertySearch.new(params, client: client).call
    captured
  end

  it "非公開物件を除外する filter を常に含む(V2-6)" do
    body = request_body_for({})

    expect(body[:query][:bool][:filter]).to include(term: { published: true })
  end

  it "価格帯 + 間取り + 徒歩分数の複合絞り込みを filter に積む(V2-1)" do
    body = request_body_for(
      { min_price: "50000", max_price: "100000", layouts: %w[1LDK 1K], max_walk_minutes: "10" }
    )

    filters = body[:query][:bool][:filter]
    expect(filters).to include(range: { price: { gte: 50_000 } })
    expect(filters).to include(range: { price: { lte: 100_000 } })
    expect(filters).to include(terms: { layout: %w[1LDK 1K] })
    expect(filters).to include(range: { min_walk_minutes: { lte: 10 } })
  end

  it "layouts がカンマ区切り文字列でも配列として扱う" do
    body = request_body_for({ layouts: "1LDK,1K" })

    expect(body[:query][:bool][:filter]).to include(terms: { layout: %w[1LDK 1K] })
  end

  it "指定地点からの円形検索と近い順ソートを組み立てる(V2-2)" do
    body = request_body_for({ lat: "35.7", lng: "139.7", radius_km: "1.5", sort: "distance" })

    expect(body[:query][:bool][:filter]).to include(
      geo_distance: { distance: "1.5km", location: { lat: 35.7, lon: 139.7 } }
    )
    expect(body[:sort]).to eq([{ "_geo_distance" => { location: { lat: 35.7, lon: 139.7 }, order: "asc", unit: "km" } }])
  end

  it "物件名・住所の日本語全文検索を must に積む(V2-3)" do
    body = request_body_for({ q: "神谷" })

    expect(body[:query][:bool][:must]).to eq([{ multi_match: { query: "神谷", fields: %w[name address] } }])
  end

  it "q が無い場合は must を組み立てない" do
    body = request_body_for({})

    expect(body[:query][:bool]).not_to have_key(:must)
  end

  it "路線名を nested query の filter にする(V2-4)" do
    body = request_body_for({ line_name: "東京メトロ南北線" })

    expect(body[:query][:bool][:filter]).to include(
      nested: { path: "stations", query: { term: { "stations.line_name" => "東京メトロ南北線" } } }
    )
  end

  it "facets=true のとき間取り件数・価格帯ヒストグラムの aggs を積む(V2-5)" do
    body = request_body_for({ facets: "true" })

    expect(body[:aggs]).to eq(
      by_layout: { terms: { field: "layout" } },
      by_price_range: {
        range: {
          field: "price",
          ranges: [{ to: 70_000 }, { from: 70_000, to: 120_000 }, { from: 120_000 }]
        }
      }
    )
  end

  it "facets が無い場合は aggs を組み立てない" do
    body = request_body_for({})

    expect(body).not_to have_key(:aggs)
  end

  it "price_asc / price_desc のソートを組み立てる" do
    expect(request_body_for({ sort: "price_asc" })[:sort]).to eq([{ price: "asc" }])
    expect(request_body_for({ sort: "price_desc" })[:sort]).to eq([{ price: "desc" }])
  end

  it "page / per_page から from / size を計算する" do
    body = request_body_for({ page: "3", per_page: "10" })

    expect(body[:from]).to eq(20)
    expect(body[:size]).to eq(10)
  end

  it "レスポンスの hits を total / properties に整形する" do
    response = {
      "hits" => {
        "total" => { "value" => 2 },
        "hits" => [{ "_source" => { "name" => "A" } }, { "_source" => { "name" => "B" } }]
      }
    }

    captured_call_result = nil
    client = double("opensearch_client", search: response)
    captured_call_result = PropertySearch.new({}, client: client).call

    expect(captured_call_result).to eq(total: 2, properties: [{ "name" => "A" }, { "name" => "B" }])
  end
end
