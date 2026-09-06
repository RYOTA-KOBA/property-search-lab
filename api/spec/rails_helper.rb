ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"

# Ridgepole 運用ではマイグレーション履歴を持たないため、
# ActiveRecord::Migration.maintain_test_schema! は呼ばない(docs/decisions.md D15/D16)。
# テスト DB のスキーマ同期は `bundle exec rake ridgepole:apply[test]` を明示的に実行する

Dir[Rails.root.join("spec", "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
