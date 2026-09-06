namespace :ridgepole do
  desc "Ridgepole で db/Schemafile を適用する(例: rake ridgepole:apply[test])"
  task :apply, [:env] do |_, args|
    env = args[:env] || "development"
    sh "bundle exec ridgepole -c config/database.yml -E #{env} --apply -f db/Schemafile"
  end

  desc "現在の DB スキーマを db/Schemafile に書き出す(手動編集の後、差分確認に使う)"
  task :export, [:env] do |_, args|
    env = args[:env] || "development"
    sh "bundle exec ridgepole -c config/database.yml -E #{env} --export -f db/Schemafile"
  end
end
