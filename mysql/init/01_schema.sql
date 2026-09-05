-- 検証用スキーマ。非正規化の検証ができるよう 1物件:N画像 / 1物件:N駅 の構造にしてある

USE property_dev;

-- 物件本体
CREATE TABLE properties (
  id                   BIGINT PRIMARY KEY AUTO_INCREMENT,
  name                 VARCHAR(255) NOT NULL,
  address              VARCHAR(255) NOT NULL,
  price                INT          NOT NULL,
  layout               VARCHAR(16)  NOT NULL,
  area_m2              DECIMAL(6,2),
  lat                  DECIMAL(10,7),
  lng                  DECIMAL(10,7),
  published            TINYINT(1)   NOT NULL DEFAULT 1,
  created_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP
);

-- 1物件 : N画像。DMS 単体では JOIN できない典型例
CREATE TABLE property_images (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  property_id BIGINT NOT NULL,
  url         VARCHAR(512) NOT NULL,
  position    INT NOT NULL DEFAULT 0,
  INDEX idx_property_id (property_id)
);

-- 1物件 : N最寄駅
CREATE TABLE property_stations (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  property_id   BIGINT NOT NULL,
  station_name  VARCHAR(128) NOT NULL,
  line_name     VARCHAR(128),
  walk_minutes  INT NOT NULL,
  INDEX idx_property_id (property_id)
);

INSERT INTO properties (name, address, price, layout, area_m2, lat, lng) VALUES
  ('王子神谷レジデンス 302', '東京都北区王子5-1-1', 92000,  '1LDK', 38.20, 35.7690, 139.7370),
  ('赤羽ハイツ 101',         '東京都北区赤羽2-3-4', 68000,  '1K',   22.50, 35.7780, 139.7210),
  ('神楽坂コート 505',       '東京都新宿区矢来町1', 148000, '2LDK', 55.10, 35.7020, 139.7350);

INSERT INTO property_images (property_id, url, position) VALUES
  (1, 'https://cdn.example.com/1_a.jpg', 0),
  (1, 'https://cdn.example.com/1_b.jpg', 1),
  (2, 'https://cdn.example.com/2_a.jpg', 0),
  (3, 'https://cdn.example.com/3_a.jpg', 0);

INSERT INTO property_stations (property_id, station_name, line_name, walk_minutes) VALUES
  (1, '王子神谷', '東京メトロ南北線', 6),
  (1, '王子',     'JR京浜東北線',     12),
  (2, '赤羽',     'JR埼京線',         8),
  (3, '神楽坂',   '東京メトロ東西線', 4);
