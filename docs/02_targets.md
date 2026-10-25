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

## 棚卸し
確認日: 2026-10-25。移行後の比較基準にする。

### 調べ方
- [../scripts/inventory.ps1](../scripts/inventory.ps1) を実行した。生データ: [inventory_2026-10-25.csv](inventory_2026-10-25.csv)
- **bd は一度も実行していない**（0.49.0 は実行しただけで daemon を起動し、JSONL を書き換えることがあるため）。
- DB は `.db`、`-wal`、`-shm` を作業用フォルダにコピーし、コピーを `sqlite3` で開いて数えた。
  最初は元の DB を `immutable=1` で開いたが、その方法では WAL の中身が読まれず、件数が古くなっていた（goto-goto などで JSONL と合わなかった）。
- git は `--no-optional-locks` で、index を書き換えないようにした。

### 全体に共通すること
- 24 か所とも、`*.db` は `beads.db` 1 つだけ。`metadata.json` は `{"database":"beads.db","jsonl_export":"issues.jsonl"}`。
  DB の `bd_version` と `.local_version` はどちらも `0.49.0`。
  → 公式の手順書の「One `.beads/*.db` file: sealed SQLite bridge」に当てはまる。
- `.beads` の中に Dolt のフォルダ（`dolt/`、`embeddeddolt/`）はない。
- issue の合計は **1,463 件**（DB の件数。tombstone を含む）。

### 一覧
状態の略: c=closed, o=open, ip=in_progress, b=blocked, t=tombstone。
「JSONL」は `issues.jsonl` の状態別件数が DB と合うか。「dirty」は DB の `dirty_issues` の行数。
「git」は `.beads` 以下の未コミットのファイル数と、upstream に対して未 push の commit 数。

| # | リポジトリ | 接頭辞 | DB 件数 | DB の状態別 | JSONL | dirty | git | hooks | 備考 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | calc_20260306 | `t` | 21 | c19 t2 | 一致 | 0 | 0 / upstream なし | pm, pc | |
| 2 | calc_20260317 | `calc_20260317` | 18 | c18 | 一致 | 0 | 0 / 0 | pm, pc | sync-state.json |
| 3 | chromeext_insta_reels | `chromeext_insta_reels` | 19 | c12 o7 | 一致 | 0 | 0 / upstream なし | pm, pc | beads.left.*, sync-state.json |
| 4 | kakeizu | `kakeizu` | 88 | c85 o3 | 一致 | 0 | 0 / **17** | pm, pc | 未 push が 17 commit |
| 5 | keihi_track | `keihi_track` | 46 | c46 | **不一致**（JSONL は c45 o1） | 1 | 1 / 0 | pm, pc | sync-state.json |
| 6 | my_tenbin_ai | `my_tenbin_ai` | 45 | c45 | 一致 | 0 | 0 / upstream なし | pm, pc | sync-state.json |
| 7 | n8n-insights-viewer | `n8n-insights-viewer` | 26 | c25 o1 | 一致 | 0 | 0 / 0 | pm, pc | |
| 8 | newsletter-ai-chat | `nac` | 22 | c22 | 一致 | 0 | 0 / 0 | pm, pc | beads.left.* |
| 9 | qr_code_create | `qr_code_create` | 108 | c96 o12 | 一致 | 0 | 0 / upstream なし | pm, pc | |
| 10 | salon-daily-fetcher | `salon-daily-fetcher` | 16 | c14 o2 | 一致 | 0 | 0 / upstream なし | pm, pc | beads.left.* |
| 11 | simple-translator | `simple-translator` | 26 | c22 ip1 o3 | 一致 | 1 | 1 / upstream なし | pm, pc | feature ブランチ上、beads.left.* |
| 12 | sql_viz_202604 | `sql_viz_202604_2` | 113 | c113 | **不一致**（JSONL は 112 件） | 108 | 1 / 0 | なし | feature ブランチ上、sync-state.json |
| 13 | sql_viz_202604_3 | `sql_viz_202604_3` | 52 | c52 | 一致 | 52 | **JSONL が git 管理外** / upstream なし | なし | |
| 14 | sql_viz_202604_old | `sql_viz_202604` | 27 | c27 | 一致 | 0 | **5** / upstream なし | なし | `core.hooksPath` が sql_viz_202604 の `.git\hooks` を指している |
| 15 | two-device-translator | `two-device-translator` | 69 | c54 ip1 o14 | 一致 | 0 | 0 / 0 | pm, pc | sync-state.json |
| 16 | bigquery-mcp | `bq` | 85 | c18 o66 t1 | 一致 | 0 | 0 / 0 | pm, pc | beads.left.*, sync-state.json |
| 17 | goto-goto | `goto` | 111 | c35 o76 | 一致 | 0 | 0 / 0 | pm, pc | |
| 18 | kuchikomi_helper | `kh` | 55 | c39 o16 | **不一致**（JSONL は 54 件、o15） | 24 | 0 / 0 | なし | |
| 19 | shien-mitsukaru | `sm` | 141 | b13 c31 ip3 o94 | 一致 | 0 | 0 / 0 | pm, pc | |
| 20 | website2026 | `website2026` | 66 | c42 o5 t19 | 一致 | 0 | 0 / 0 | pm, pc | |
| 21 | y2026 | `kuroneko-taiwan-2026-20260318` | 150 | c68 o82 | 一致 | 0 | 0 / 0 | なし | |
| 22 | takatsu-connect-advisor | `takatsu-connect-advisor` | 110 | c61 ip1 o48 | **不一致**（JSONL は c60 o49） | 14 | 1 / upstream なし | husky の pre-commit（bd とは別） | feature ブランチ上、beads.left.*, sync-state.json |
| 23 | tc-wrapper | `tc` | 22 | c18 o4 | 一致 | 1 | 1 / 0 | pm, pc | |
| 24 | minecraft_piece | `minecraft_piece` | 27 | b1 c26 | 一致 | 0 | 0 / 0 | 0.49.0 の hooks 5 種 + `.backup` | export-state/ |

hooks の略: pm=post-merge, pc=pre-commit（どちらも bd が入れたもの）。

### 分かったこと
- **DB の方が JSONL より新しいものが 4 件ある**（keihi_track、sql_viz_202604、kuchikomi_helper、takatsu-connect-advisor）。
  最新のデータは DB にある。移行は DB から取り出す必要があり、JSONL だけをバックアップにするのは不十分。
  公式スクリプトは `.beads` を丸ごとコピーして DB を読むので、この点は問題ない。
- dirty が 0 でないのに件数が合うものもある（sql_viz_202604_3 は 52 件すべてが dirty）。
  件数は同じでも中身が違う可能性がある。移行後の比較は件数だけでなく、issue ごとの中身（id、状態、更新日時）でも行う。
- **bd の pre-commit hook は `bd sync --flush-only` を呼び、失敗すると exit 1 で commit を止める。**
  1.3.2 で `bd sync` がなくなっているか、動きが変わっていれば、移行したリポジトリで commit できなくなる。
  移行するたびに `bd hooks install` で入れ直すか、hooks を外す必要がある。bd の hooks があるのは 18 か所。
- 未 push の commit がある: kakeizu（17）。`.beads` に未コミットの変更がある: sql_viz_202604_old（5）、keihi_track、simple-translator、sql_viz_202604、takatsu-connect-advisor、tc-wrapper（各 1）。
- feature ブランチの上にあるもの: simple-translator、sql_viz_202604、takatsu-connect-advisor。
- `beads.left.jsonl` / `beads.left.meta.json`（マージの途中で残ったものとみられる）、`sync-state.json`、`export-state/` は、新しい版での扱いが分からない。
