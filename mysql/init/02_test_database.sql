-- property_dev は MYSQL_DATABASE 環境変数でコンテナが自動作成するが、
-- RSpec 用の property_test は対象外なのでここで作成する(docs/decisions.md D15)。
-- テーブルスキーマはこの中で作らない。api/db/Schemafile を正として Ridgepole が適用する。
CREATE DATABASE IF NOT EXISTS property_test CHARACTER SET utf8mb4;
GRANT ALL PRIVILEGES ON property_test.* TO 'app'@'%';
FLUSH PRIVILEGES;
