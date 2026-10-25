# 03 リハーサル（全 24 か所のコピーで移行を通す）

確認日: 2026-10-25

## やり方
- [../scripts/rehearsal-all.ps1](../scripts/rehearsal-all.ps1) が、棚卸しの一覧（[inventory_2026-10-25.csv](inventory_2026-10-25.csv)）の順に [../scripts/trial-cutover.ps1](../scripts/trial-cutover.ps1) を実行した。
- 元の `.beads` はコピーするだけで開かない。作業はすべて `work/rehearsal-2026-10-25b/<ルート>__<リポジトリ>/` で行った（`.gitignore` で除外）。
- 1 か所あたりの手順:
  1. `.beads` のコピーを v0.49.6 で `init --force` する
  2. v0.49.6 で `--allow-stale export` する（JSONL は取り込まず、DB の中身をそのまま出す）
  3. 日時を同じ時刻の UTC 表記にそろえる（上流の不具合 #5765 の回避。[01_current-state.md](01_current-state.md) の「不具合」の節）
  4. 1.3.2 で `init --from-jsonl` する
  5. 1.3.2 で `export --all` する
  6. 突き合わせる
- 突き合わせの内容:
  - 元の DB と各 export: id ごとの status、title、ラベル数、依存数、コメント数
  - v0.49.6 の export と 1.3.2 の export: 公式スクリプトの `normalize_export` と同じ規則で全項目
  - 参考: 元の `issues.jsonl` と DB の中身の全項目

## 結果
**24 か所すべて成功**。生データ: [rehearsal_2026-10-25.csv](rehearsal_2026-10-25.csv)

- tombstone（削除済み）を除く **1,441 件が全項目で一致**した。
- tombstone の 22 件は 1.3.2 に引き継がれなかった（calc_20260306 が 2 件、bigquery-mcp が 1 件、website2026 が 19 件）。抜けた id は、元の DB で `status=tombstone` かつ `deleted_at` ありのものと一致した。
- 元の `.beads` のハッシュは、24 か所とも実行の前後で同じだった。
- 1 か所あたり 14〜18 秒。

| # | リポジトリ | 元の DB | 1.3.2 | tombstone | 全項目の違い | 元の JSONL と DB の違い（参考） |
|---|---|---|---|---|---|---|
| 1 | calc_20260306 | 21 | 19 | 2 | 0 | なし |
| 2 | calc_20260317 | 18 | 18 | 0 | 0 | なし |
| 3 | chromeext_insta_reels | 19 | 19 | 0 | 0 | なし |
| 4 | kakeizu | 88 | 88 | 0 | 0 | なし |
| 5 | keihi_track | 46 | 46 | 0 | 0 | 1 件（status、closed_at など） |
| 6 | my_tenbin_ai | 45 | 45 | 0 | 0 | なし |
| 7 | n8n-insights-viewer | 26 | 26 | 0 | 0 | なし |
| 8 | newsletter-ai-chat | 22 | 22 | 0 | 0 | なし |
| 9 | qr_code_create | 108 | 108 | 0 | 0 | なし |
| 10 | salon-daily-fetcher | 16 | 16 | 0 | 0 | なし |
| 11 | simple-translator | 26 | 26 | 0 | 0 | なし |
| 12 | sql_viz_202604 | 113 | 113 | 0 | 0 | DB にだけある issue が 1 件 |
| 13 | sql_viz_202604_3 | 52 | 52 | 0 | 0 | なし |
| 14 | sql_viz_202604_old | 27 | 27 | 0 | 0 | なし |
| 15 | two-device-translator | 69 | 69 | 0 | 0 | なし |
| 16 | bigquery-mcp | 85 | 84 | 1 | 0 | なし |
| 17 | goto-goto | 111 | 111 | 0 | 0 | なし |
| 18 | kuchikomi_helper | 55 | 55 | 0 | 0 | DB にだけある issue が 1 件。ほかに依存 6 件、説明文・タイトル 2 件など |
| 19 | shien-mitsukaru | 141 | 141 | 0 | 0 | なし |
| 20 | website2026 | 66 | 47 | 19 | 0 | なし |
| 21 | y2026 | 150 | 150 | 0 | 0 | なし |
| 22 | takatsu-connect-advisor | 110 | 110 | 0 | 0 | status 2 件、updated_at 2 件など |
| 23 | tc-wrapper | 22 | 22 | 0 | 0 | なし |
| 24 | minecraft_piece | 27 | 27 | 0 | 0 | なし |

### 元の JSONL と DB の違いについて
4 か所（keihi_track、sql_viz_202604、kuchikomi_helper、takatsu-connect-advisor）は、棚卸しで「DB の方が新しい」としたものと同じ。
違いのある issue は、**どれも DB の `updated_at` の方が新しい**。たとえば kh-adx.12 は、JSONL では `15:09:47Z`、DB では `15:16:19Z` だった。
DB にだけある issue もある（`kh-9gx.5`、`sql_viz_202604_2-ldb`）。JSONL の方が新しいものはなかった。
→ DB から移行するのが正しい。

## 1 回目のリハーサルで分かったこと（`work/rehearsal-2026-10-25`）
1 回目は 7 / 24 しか成功しなかった。直したことは 2 つ。
1. **15 か所が v0.49.6 の export で止まった。**
   `Error: Database out of sync with JSONL. Run 'bd sync --import-only' to fix.` が出た。
   言われたとおりに取り込むと、DB にしかない新しい変更を古い JSONL で上書きしてしまう。
   取り込まずに `--allow-stale` を付けて、DB の中身をそのまま export するように直した。
2. **3 か所で 1.3.2 の件数が減った。** 調べると、減ったのは tombstone だけだった。
   引き継がれない tombstone は想定内として別に数え、成否の判定から外した。

## 引き継がれないもの（まとめ）
- events（変更の履歴）
- tombstone（削除済みの issue）22 件
- DB の中の設定（`config` テーブル。issue_prefix は `--prefix` で引き継ぐ）

元の `.beads` はバックアップとして丸ごと残すので、どれも完全に失われるわけではない。
