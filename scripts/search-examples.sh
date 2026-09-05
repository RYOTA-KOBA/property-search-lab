#!/bin/bash
# docs/verification-plan.md の V2 で求めている6要件を、それぞれ単一クエリで表現できるか確認する
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

run() {
  local title="$1"
  local body="$2"
  echo "=== ${title} ==="
  curl -s -XPOST "${OS_ENDPOINT}/properties_search/_search" \
    -H 'Content-Type: application/json' \
    -d "$body" | jq .
  echo
}

# 1. 価格帯 + 間取り + 徒歩分数の複合絞り込み
# スコア計算が不要な絞り込み条件なので filter に入れてキャッシュを効かせる
run "1. 価格帯 + 間取り + 徒歩分数" '{
  "query": {
    "bool": {
      "filter": [
        { "range": { "price": { "lte": 100000 } } },
        { "terms": { "layout": ["1LDK", "1K"] } },
        { "range": { "min_walk_minutes": { "lte": 10 } } }
      ]
    }
  }
}'

# 2. 指定地点から N km 圏内、近い順
# geo_distance も絞り込みなので filter。並び順だけ _geo_distance sort で別に指定する
run "2. 指定地点から2km圏内、近い順" '{
  "query": {
    "bool": {
      "filter": [
        {
          "geo_distance": {
            "distance": "2km",
            "location": { "lat": 35.7690, "lon": 139.7370 }
          }
        }
      ]
    }
  },
  "sort": [
    {
      "_geo_distance": {
        "location": { "lat": 35.7690, "lon": 139.7370 },
        "order": "asc",
        "unit": "km"
      }
    }
  ]
}'

# 3. 物件名・住所の日本語全文検索
# 関連度を評価したいキーワード検索なので must に入れる(filter ではスコアが付かない)
run "3. 物件名・住所の全文検索(神谷)" '{
  "query": {
    "multi_match": {
      "query": "神谷",
      "fields": ["name", "address"]
    }
  }
}'

# 4. 特定路線かつ徒歩5分以内の駅を持つ物件
# stations は nested なので、同じ配列要素内での路線と徒歩分数の組み合わせを
# nested query でまとめて評価する(まとめないと別の駅の条件と混同してしまう)
run "4. 東京メトロ東西線かつ徒歩5分以内の駅を持つ物件" '{
  "query": {
    "nested": {
      "path": "stations",
      "query": {
        "bool": {
          "filter": [
            { "term": { "stations.line_name": "東京メトロ東西線" } },
            { "range": { "stations.walk_minutes": { "lte": 5 } } }
          ]
        }
      }
    }
  }
}'

# nested の効果を確認する反例: 物件1は「南北線・6分」と「京浜東北線・12分」を別の駅として持つ。
# nested なら路線と徒歩分数の組が同じ駅内で一致しないとマッチしないため、
# 「京浜東北線 かつ 徒歩10分以内」は物件1にヒットしない(nested を使わず配列をフラットに
# フィルタすると誤って物件1にもヒットしてしまう)
run "4b. (反例) 京浜東北線かつ徒歩10分以内 → 物件1はヒットしないはず" '{
  "query": {
    "nested": {
      "path": "stations",
      "query": {
        "bool": {
          "filter": [
            { "term": { "stations.line_name": "JR京浜東北線" } },
            { "range": { "stations.walk_minutes": { "lte": 10 } } }
          ]
        }
      }
    }
  }
}'

# 5. 間取りごとの件数、価格帯ヒストグラム(ファセット)
# size:0 で検索結果本体は返さず、集計結果だけ使う
run "5. 間取り別件数 + 価格帯ヒストグラム" '{
  "size": 0,
  "aggs": {
    "by_layout": { "terms": { "field": "layout" } },
    "by_price_range": {
      "range": {
        "field": "price",
        "ranges": [
          { "to": 70000 },
          { "from": 70000, "to": 120000 },
          { "from": 120000 }
        ]
      }
    }
  }
}'

# 6. 非公開物件の除外
# published は絞り込み条件そのものなので term filter に入れる
run "6. 公開中の物件のみ" '{
  "query": {
    "bool": {
      "filter": [
        { "term": { "published": true } }
      ]
    }
  }
}'
