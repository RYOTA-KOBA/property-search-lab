# 旧 reference/schema.sql に含めていたシードデータ(docs/decisions.md D15 で Ridgepole 導入に伴い移植)。
# find_or_create_by! で idempotent にし、何度流しても重複登録しないようにする。

seed_properties = [
  {
    name: "王子神谷レジデンス 302", address: "東京都北区王子5-1-1",
    price: 92_000, layout: "1LDK", area_m2: 38.20, lat: 35.7690, lng: 139.7370,
    images: ["https://cdn.example.com/1_a.jpg", "https://cdn.example.com/1_b.jpg"],
    stations: [
      { station_name: "王子神谷", line_name: "東京メトロ南北線", walk_minutes: 6 },
      { station_name: "王子", line_name: "JR京浜東北線", walk_minutes: 12 }
    ]
  },
  {
    name: "赤羽ハイツ 101", address: "東京都北区赤羽2-3-4",
    price: 68_000, layout: "1K", area_m2: 22.50, lat: 35.7780, lng: 139.7210,
    images: ["https://cdn.example.com/2_a.jpg"],
    stations: [
      { station_name: "赤羽", line_name: "JR埼京線", walk_minutes: 8 }
    ]
  },
  {
    name: "神楽坂コート 505", address: "東京都新宿区矢来町1",
    price: 148_000, layout: "2LDK", area_m2: 55.10, lat: 35.7020, lng: 139.7350,
    images: ["https://cdn.example.com/3_a.jpg"],
    stations: [
      { station_name: "神楽坂", line_name: "東京メトロ東西線", walk_minutes: 4 }
    ]
  }
]

seed_properties.each do |attrs|
  images = attrs.delete(:images)
  stations = attrs.delete(:stations)

  property = Property.find_or_create_by!(name: attrs[:name]) do |p|
    p.assign_attributes(attrs)
  end

  images.each_with_index do |url, position|
    property.property_images.find_or_create_by!(url: url) { |img| img.position = position }
  end

  stations.each do |station_attrs|
    property.property_stations.find_or_create_by!(station_attrs)
  end
end
