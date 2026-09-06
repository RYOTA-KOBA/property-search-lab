namespace :rbs do
  desc "rbs-inline と rbs_rails で sig/ 配下の型定義を再生成する"
  task :generate do
    sh "bundle exec rbs-inline --opt-out --output=sig/generated app lib"
    sh "bundle exec rake rbs_rails:all"
  end
end
