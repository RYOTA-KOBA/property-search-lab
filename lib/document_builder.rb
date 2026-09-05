def build_document(mysql, property_id)
  # mysql2 にバインドパラメータ API が無いため、to_i で整数に丸めてから埋め込む
  id = property_id.to_i

  property = mysql.query("SELECT * FROM properties WHERE id = #{id}").first
  return nil unless property

  images = mysql.query(
    "SELECT url FROM property_images WHERE property_id = #{id} ORDER BY position"
  ).to_a

  stations = mysql.query(
    "SELECT station_name, line_name, walk_minutes FROM property_stations WHERE property_id = #{id}"
  ).to_a

  {
    id: property["id"],
    name: property["name"],
    address: property["address"],
    price: property["price"],
    layout: property["layout"],
    area_m2: property["area_m2"]&.to_f,
    published: property["published"] == 1,
    location: geo_point(property["lat"], property["lng"]),

    min_walk_minutes: stations.map { |s| s["walk_minutes"] }.min,
    station_names: stations.map { |s| s["station_name"] }.uniq,

    stations: stations.map do |s|
      {
        station_name: s["station_name"],
        line_name: s["line_name"],
        walk_minutes: s["walk_minutes"]
      }
    end,

    image_urls: images.map { |i| i["url"] },
    thumbnail_url: images.first&.fetch("url"),

    created_at: format_time(property["created_at"]),
    updated_at: format_time(property["updated_at"]),
    indexed_at: format_time(Time.now.utc)
  }
end

def geo_point(lat, lng)
  return nil if lat.nil? || lng.nil?

  { lat: lat.to_f, lon: lng.to_f }
end

def format_time(time)
  return nil if time.nil?

  time.strftime("%Y-%m-%dT%H:%M:%S")
end
