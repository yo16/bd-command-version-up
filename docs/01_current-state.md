# 01 現状と最新版

確認日: 2026-10-25

## 現在の bd
| 項目 | 値 | 確認方法 |
|---|---|---|
| 版 | `bd version 0.49.0 (dev)` | `bd version` |
| 実体 | `C:\Users\yoichiro\go\bin\bd.exe`（46,019,584 バイト、更新 2026-01-25 10:39:50） | `Get-Command bd -All` |
| PATH 上の bd | 上記の 1 つだけ | `Get-Command bd -All` |
| 入手方法 | `go install`（module `github.com/steveyegge/beads v0.49.0`、go1.25.6 でビルド） | `go version -m bd.exe` |
| 保存先 | SQLite（依存に `github.com/ncruces/go-sqlite3 v0.30.4`） | 同上 |

## 最新版
- 最新の安定版: **v1.3.2**（2026-10-24 公開）
- リポジトリは `steveyegge/beads` から **`gastownhall/beads`** に移っている（旧名は転送される）。
- 0.49.0 より後の安定版:
  0.49.3〜0.49.6, 0.50.1〜0.50.3, 0.51.0, 0.52.0, 0.55.4, 0.56.1, 0.57.0〜0.62.0, 0.63.3,
  1.0.0〜1.0.4, 1.1.0, 1.1.2, 1.2.2, 1.3.0, 1.3.1, 1.3.2
  （1.2.1 は事故リリースとして取り下げられている）
- 出典: `gh release list --repo steveyegge/beads`。リリースノート全文は
  [../references/release-notes_2026-10-25.txt](../references/release-notes_2026-10-25.txt)

## リリースノートから分かった重要な変更
| 版 | 内容 | ノート内の位置 |
|---|---|---|
| 0.55〜0.56 | wisp（一時データ）を Dolt 側へ移す。`bd migrate wisps` 追加 | v0.56.1 |
| 0.57.0 | **最初の bd コマンドで SQLite から Dolt へ自動移行する**機能（bd-3dx）。SQLite→Dolt 移行の不具合修正多数 | v0.57.0 |
| 0.58.0 | `bd init --backend` と SQLite 非推奨の告知。その後「Beads Classic SQLite backend and migration infrastructure」を削除するコミットあり | v0.58.0 |
| 1.0.0 | スキーマ版 11。`bd onboard` の記述を `bd prime` に置き換え（AGENTS.md） | v1.0.0 |
| 1.3.0 | **Dolt が唯一の保存先。SQLite は削除**。`.beads/metadata.json` に `"backend": "sqlite"` が残っていると開けず、修正方法が表示される。古い DB からは `bd migrate legacy-sqlite --source-db PATH --output PATH` で JSONL を読み取り専用で取り出せる。アップグレード後は `bd upgrade review` で差分を読むよう推奨 | v1.3.0 |
| 1.3.2 | スキーマ移行なし（Dolt 2.2.0 のまま）。1.3.0 以降で migration 0059 を通ったストアに関する注意書きあり（アップグレード前に読む） | v1.3.2 |

## 結論（暫定）
- 0.49.0（SQLite）から 1.3.2（Dolt のみ）へは、**保存形式の移行が必須**。そのまま新しい版で開くことはできない。
- 経路の候補:
  1. 途中の版（0.57 系など、自動移行を持つ版）で SQLite→Dolt を済ませてから 1.3.2 に上げる。
  2. 1.3.2 で `bd migrate legacy-sqlite` により JSONL を取り出し、Dolt のストアへ取り込む。
- どちらを選ぶかはステップ 3 で決める。

## 未確認（次にやること）
- [ ] 公式の `docs/getting-started/upgrading.md`（v1.3.2）を読む。版ごとの手順と複数クローンの扱いが書かれている
- [ ] `docs/RECOVERY.md`、`docs/recovery/` の内容
- [ ] 1.3.0 の「v1.2.2 users 向け Breaking changes」と CHANGELOG `[1.2.1]` 節の要点
- [ ] 1.3.2 の migration 0059 の注意書きの全文
- [ ] Windows での入手方法（`go install` を続けるか、リリースバイナリ / `install.ps1` にするか。新しい版は CGO が必要な可能性あり）
- [ ] bd daemon が動いているか
