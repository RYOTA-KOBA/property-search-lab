# 検証計画

このリポジトリのゴールは動くものを作ることではなく、**技術選定の判断根拠を得ること**。
各シナリオには合格基準を設け、結果を `docs/results.md` に追記していく。

## V1. マッピング設計が意図通りか

**確認方法**

```bash
# analyzer の動作確認
curl -XPOST "$OS_ENDPOINT/properties_search/_analyze" \
  -d '{"analyzer":"ja_text","text":"東京都北区王子神谷レジデンス"}'
```

**合格基準**

- 「王子神谷」「レジデンス」が意図した粒度で分割される
- 表記ゆれ(全角/半角、カタカナ長音)が正規化される
- `dynamic: strict` により、未定義フィールドを含むドキュメントの投入が拒否される

## V2. 検索クエリが表現しきれるか

物件検索で必要な条件が Query DSL で表現できるかを確認する。
一つでも表現できないものがあれば、この構成の採用可否に直結する。

| # | 要件 | 使う機能 |
|---|---|---|
| 1 | 価格帯 + 間取り + 徒歩分数の複合絞り込み | `bool.filter` + `range` + `terms` |
| 2 | 指定地点から N km 圏内、近い順 | `geo_distance` + `_geo_distance` sort |
| 3 | 物件名・住所の日本語全文検索 | `multi_match` + kuromoji |
| 4 | 特定路線かつ徒歩5分以内の駅を持つ物件 | `nested` |
| 5 | 間取りごとの件数、価格帯ヒストグラム(ファセット) | `terms` / `range` aggregation |
| 6 | 非公開物件の除外 | `term` filter |

**合格基準**: 6件すべてが単一クエリで表現でき、意図した結果が返る。

## V3. 非正規化ロジックが成立するか

**確認方法**: 子テーブルを更新し、親ドキュメントに波及するかを見る。

```bash
docker compose exec mysql mysql -uapp -papppass property_dev -e "
  INSERT INTO property_stations (property_id, station_name, line_name, walk_minutes)
  VALUES (2, '赤羽岩淵', '東京メトロ南北線', 3);
"
./scripts/emit-cdc-event.sh insert property_stations 2
```

**合格基準**: 物件2のドキュメントの `min_walk_minutes` が 8 → 3 に更新される。

これは **DMS 単体では実現できない部分**であり、Lambda を挟む構成の妥当性を示す中核の検証。

## V4. DMS イベント形式のパースが正しいか

**確認方法**: `reference/dms-event-samples/` の各イベント(insert / update / delete)を
Kinesis に流し、Lambda が正しく処理するかを見る。

**合格基準**

- `metadata.operation` が `insert` / `update` / `load` のとき upsert される
- `metadata.operation` が `delete` のときドキュメントが削除される
- `metadata.record-type` が `control` のイベントは無視される(テーブル作成通知など)
- 未知の operation が来ても Lambda が落ちない

## V5. 論理削除がインデックスから落ちるか

**合格基準**: `published = 0` に更新した物件のドキュメントが削除され、`_doc/{id}` が 404 を返す。

## V6. マッピング変更の無停止入れ替え

**確認方法**

```bash
# reference/index-mapping.json を編集してから
./scripts/create-index.sh v2
./scripts/full-reindex.sh properties_v2
./scripts/create-index.sh v2   # エイリアスを v2 へ張り替え
```

**合格基準**: 検索スクリプトを `properties_search` 向けに走らせたまま切り替えても、
エラーにならず新マッピングの結果に切り替わる。

## V7. フルリインデックスの所要時間

**確認方法**: シードデータを1万件に増やして `full-reindex.sh` の実行時間を測る。

**合格基準**: 明確な閾値は設けない。**件数あたりの所要時間を記録し、
本番の物件件数に外挿して夜間バッチの実行時間が現実的かを判断する**のが目的。

---

## ローカルでは検証しないこと(AWS 検証アカウントで確認する)

以下はローカルの模倣物で測っても本番の参考値にならない。
上記 V1〜V7 が通った後、AWS で小さく DMS タスクを1本立てて確認する。

- Aurora の binlog 設定(`binlog_format=ROW`、binlog 保持期間)が正しく効くか
- **INSERT から検索反映までの同期ラグの実測値** — 業務側と合意すべき数字なので、
  憶測でなく実測値を持つこと
- DMS タスク停止からの復旧。binlog 保持期間を超えた場合の欠損挙動
- OpenSearch Service のノードサイジングとシャード設計

## 最終的に出したい結論

検証完了時に、以下に答えられる状態にする。

1. 物件検索の要件は OpenSearch の Query DSL で表現しきれるか
2. 複数テーブルの非正規化は Lambda で無理なく書けるか。その保守コストはどの程度か
3. 結果整合性のラグは業務上許容できる水準か
4. **そもそも RDB のインデックス最適化では足りないのか**(これが最重要)
