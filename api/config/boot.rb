ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

require "dotenv"
# リポジトリ直下の .env(docker-compose や scripts/ と共有)を読む。
# dotenv-rails ではなく素の dotenv を使い、Rails.root ではなく1つ上の階層を明示的に指定する
Dotenv.load(File.expand_path("../../.env", __dir__))
