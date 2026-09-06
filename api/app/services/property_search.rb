# docs/verification-plan.md の V2 で確認したクエリ DSL(scripts/search-examples.sh と同じ形)を
# HTTP のクエリパラメータから組み立てる。OpenSearch の _source をほぼそのまま返す
# (docs/architecture.md の「レスポンスをほぼそのまま変換できる」を実地で確認する狙い)。
class PropertySearch
  DEFAULT_PER_PAGE = 20
  INDEX_NAME = "properties_search".freeze

  # client を渡すとそれを使う(テストでダブルを注入するため)。省略時は OpenSearch::Client を都度生成する
  def initialize(params, client: nil)
    @params = params
    @client = client
  end

  def call
    response = client.search(index: INDEX_NAME, body: request_body)
    result = {
      total: response.dig("hits", "total", "value"),
      properties: response["hits"]["hits"].map { |hit| hit["_source"] }
    }
    result[:facets] = response["aggregations"] if facets?
    result
  end

  private

  attr_reader :params

  def client
    @client ||= OpenSearch::Client.new(host: ENV.fetch("OS_ENDPOINT"))
  end

  def request_body
    query = { bool: { filter: filters } }
    query[:bool][:must] = [{ multi_match: { query: params[:q], fields: %w[name address] } }] if params[:q].present?

    body = { query: query, from: (page - 1) * per_page, size: per_page }
    body[:sort] = sort_clause if sort_clause
    body[:aggs] = aggregations if facets?
    body
  end

  def facets?
    ActiveModel::Type::Boolean.new.cast(params[:facets])
  end

  # docs/verification-plan.md V2 の5番(間取り別件数・価格帯ヒストグラム)に対応
  def aggregations
    {
      by_layout: { terms: { field: "layout" } },
      by_price_range: {
        range: {
          field: "price",
          ranges: [{ to: 70_000 }, { from: 70_000, to: 120_000 }, { from: 120_000 }]
        }
      }
    }
  end

  def filters
    [
      { term: { published: true } },
      *price_filters,
      (layouts.present? ? { terms: { layout: layouts } } : nil),
      (params[:max_walk_minutes].present? ? { range: { min_walk_minutes: { lte: params[:max_walk_minutes].to_i } } } : nil),
      (geo_search? ? geo_distance_filter : nil),
      (params[:line_name].present? ? nested_line_filter : nil)
    ].compact
  end

  def price_filters
    [
      (params[:min_price].present? ? { range: { price: { gte: params[:min_price].to_i } } } : nil),
      (params[:max_price].present? ? { range: { price: { lte: params[:max_price].to_i } } } : nil)
    ].compact
  end

  def layouts
    case params[:layouts]
    when Array then params[:layouts]
    when String then params[:layouts].split(",")
    else []
    end
  end

  def geo_search?
    params[:lat].present? && params[:lng].present? && params[:radius_km].present?
  end

  def geo_point
    { lat: params[:lat].to_f, lon: params[:lng].to_f }
  end

  def geo_distance_filter
    { geo_distance: { distance: "#{params[:radius_km]}km", location: geo_point } }
  end

  def nested_line_filter
    { nested: { path: "stations", query: { term: { "stations.line_name" => params[:line_name] } } } }
  end

  def sort_clause
    case params[:sort]
    when "price_asc" then [{ price: "asc" }]
    when "price_desc" then [{ price: "desc" }]
    when "distance"
      geo_search? ? [{ "_geo_distance" => { location: geo_point, order: "asc", unit: "km" } }] : nil
    end
  end

  def page
    [params[:page].to_i, 1].max
  end

  def per_page
    value = params[:per_page].to_i
    value.positive? ? value : DEFAULT_PER_PAGE
  end
end
