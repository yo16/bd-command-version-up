# 02 対象の検索と棚卸し

## 検索結果
確認日: 2026-10-25

検索方法（各ルートの直下 1 階層にある `.beads` を探す）:

```powershell
Get-ChildItem -Path D:\Public\github\yo16, D:\Public\github\smallpiece2024, D:\Public\github\machinokikakushitsu, D:\Public\github\kuronekotaiwan-matsuri, D:\Public\github\takatsu-connect, D:\Public\github\small-piece-2023 -Directory -Depth 1 -Filter .beads -Force -ErrorAction SilentlyContinue
```

計 24 か所。

| # | ルート | リポジトリ |
|---|---|---|
| 1 | yo16 | calc_20260306 |
| 2 | yo16 | calc_20260317 |
| 3 | yo16 | chromeext_insta_reels |
| 4 | yo16 | kakeizu |
| 5 | yo16 | keihi_track |
| 6 | yo16 | my_tenbin_ai |
| 7 | yo16 | n8n-insights-viewer |
| 8 | yo16 | newsletter-ai-chat |
| 9 | yo16 | qr_code_create |
| 10 | yo16 | salon-daily-fetcher |
| 11 | yo16 | simple-translator |
| 12 | yo16 | sql_viz_202604 |
| 13 | yo16 | sql_viz_202604_3 |
| 14 | yo16 | sql_viz_202604_old |
| 15 | yo16 | two-device-translator |
| 16 | smallpiece2024 | bigquery-mcp |
| 17 | smallpiece2024 | goto-goto |
| 18 | smallpiece2024 | kuchikomi_helper |
| 19 | smallpiece2024 | shien-mitsukaru |
| 20 | machinokikakushitsu | website2026 |
| 21 | kuronekotaiwan-matsuri | y2026 |
| 22 | takatsu-connect | takatsu-connect-advisor |
| 23 | takatsu-connect | tc-wrapper |
| 24 | small-piece-2023 | minecraft_piece |

## 注意
- 上の検索は `リポジトリ\.beads` の深さだけを見ている。もっと深い場所にある `.beads` は拾っていない（必要なら別途確認する）。
- `sql_viz_202604_old` のように使わなくなったものも含まれる。全部を移行するかは決めていない。

## 棚卸し（未実施）
各リポジトリについて次を取る予定。移行後の比較基準にする。
- `.beads` の中身（ファイル一覧、DB と JSONL のサイズ、`metadata.json` / `config.yaml` の内容）
- issue 件数、状態別件数（open / in_progress / closed）
- git の状態（`.beads/*.jsonl` が commit 済みか、未 push の変更があるか）
- bd が入れた git hooks の有無
