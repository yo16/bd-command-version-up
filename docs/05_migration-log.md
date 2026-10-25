# 05 移行の記録

手順は [04_method.md](04_method.md)。1 件ずつ [../scripts/migrate-repo.ps1](../scripts/migrate-repo.ps1) で移行し、
エージェント向け文書は [../scripts/fix-agent-docs.ps1](../scripts/fix-agent-docs.ps1) で直し、差分を見てから commit する（push はしない）。
作業フォルダは `work/cutover-2026-10-25/<ルート>__<リポジトリ>/`（`build/`、`replaced/.beads`（入れ替える前の .beads）、`migrate.json`、`build.log`）。

## 一覧
| # | リポジトリ | 日時 | 件数（元 → 1.3.2） | tombstone | hooks を外した | commit | 備考 |
|---|---|---|---|---|---|---|---|
| 1 | yo16/sql_viz_202604_old | 2026-10-25 | 27 → 27 | 0 | pre-commit, post-merge | `c9343d4`（dev） | 4a の 1 件目。下の「1 件目で分かったこと」 |
| 2 | yo16/calc_20260317 | 2026-10-25 | 18 → 18 | 0 | pre-commit, post-merge | `85ebfb6`（dev） | 4a の 2 件目。AGENTS.md も commit。本物の issue への書き込みで自動の書き出しを確認 |

### 4b（残り 22 件、2026-10-25）
[../scripts/migrate-all.ps1](../scripts/migrate-all.ps1) で 1 件ずつ移行し、[../scripts/commit-all.ps1](../scripts/commit-all.ps1)（中身は [../scripts/commit-repo.ps1](../scripts/commit-repo.ps1)）で commit した。**22 / 22 成功。** 1 件あたり 23〜40 秒。

| # | リポジトリ | 件数（元 → 1.3.2） | tombstone | hooks を外した | commit | 文書 |
|---|---|---|---|---|---|---|
| 3 | yo16/calc_20260306 | 21 → 19 | 2 | pre-commit, post-merge | `e287aa7`（dev） | テンプレート外。直すところなし |
| 4 | yo16/chromeext_insta_reels | 19 → 19 | 0 | pre-commit, post-merge | `667df55`（dev） | AGENTS.md |
| 5 | yo16/kakeizu | 88 → 88 | 0 | pre-commit, post-merge | `fe06e22`（dev） | AGENTS.md |
| 6 | yo16/keihi_track | 46 → 46 | 0 | pre-commit, post-merge | `f49ec7d`（dev） | AGENTS.md |
| 7 | yo16/my_tenbin_ai | 45 → 45 | 0 | pre-commit, post-merge | `764d1f0`（dev） | AGENTS.md |
| 8 | yo16/n8n-insights-viewer | 26 → 26 | 0 | pre-commit, post-merge | `beee5f8`（main） | AGENTS.md |
| 9 | yo16/newsletter-ai-chat | 22 → 22 | 0 | pre-commit, post-merge | `39b6c5a`（dev） | AGENTS.md |
| 10 | yo16/qr_code_create | 108 → 108 | 0 | pre-commit, post-merge | `62ba678`（dev） | AGENTS.md |
| 11 | yo16/salon-daily-fetcher | 16 → 16 | 0 | pre-commit, post-merge | `62c697e`（dev） | AGENTS.md |
| 12 | yo16/simple-translator | 26 → 26 | 0 | pre-commit, post-merge | `d87a18e`（feature/bd-simple-translator-c2n.5） | AGENTS.md |
| 13 | yo16/sql_viz_202604 | 113 → 113 | 0 | （なし） | `9166375`（feature/bd-sql_viz_202604_2-ldb） | AGENTS.md |
| 14 | yo16/sql_viz_202604_3 | 52 → 52 | 0 | （なし） | `650b16f`（dev） | AGENTS.md。`.beads` は git の管理外なので `.gitignore` と AGENTS.md だけ |
| 15 | yo16/two-device-translator | 69 → 69 | 0 | pre-commit, post-merge | `bd1c45e`（dev） | AGENTS.md |
| 16 | smallpiece2024/bigquery-mcp | 85 → 84 | 1 | pre-commit, post-merge | `1e3bb5f`（dev） | AGENTS.md（手で直した） |
| 17 | smallpiece2024/goto-goto | 111 → 111 | 0 | pre-commit, post-merge | `d84fb49`（main） | AGENTS.md、CLAUDE.md（手で直した）。`.gitignore` を新しく作った |
| 18 | smallpiece2024/kuchikomi_helper | 55 → 55 | 0 | （なし） | `8081327`（main） | AGENTS.md なし。CLAUDE.md は直すところなし |
| 19 | smallpiece2024/shien-mitsukaru | 141 → 141 | 0 | pre-commit, post-merge | `5fda8fe`（main） | AGENTS.md |
| 20 | machinokikakushitsu/website2026 | 66 → 47 | 19 | pre-commit, post-merge | `02e27f3`（dev） | AGENTS.md（手で直した） |
| 21 | kuronekotaiwan-matsuri/y2026 | 150 → 150 | 0 | （なし） | `62a4eb1`（main） | AGENTS.md |
| 22 | takatsu-connect/takatsu-connect-advisor | 110 → 110 | 0 | pre-commit, post-merge（使われていない `.git/hooks` のもの） | `7626ee5`（feature/bd-takatsu-connect-advisor-4l4.2） | AGENTS.md。commit のときに husky の lint-staged が走った |
| 23 | takatsu-connect/tc-wrapper | 22 → 22 | 0 | pre-commit, post-merge | `577493f`（main） | テンプレート外。直すところなし |
| 24 | small-piece-2023/minecraft_piece | 27 → 27 | 0 | pre-commit, post-merge, pre-push, post-checkout, prepare-commit-msg | `2dbd518`（develop） | テンプレート外。直すところなし。`.backup` の hooks は残した |

- どの commit にも、bd と関係のない変更は含めていない（commit の前に、ほかに `git add` 済みの変更がないことを確かめた）。push はしていない。
- `.beads/interactions.jsonl` の削除を 21 件で commit した。バックアップで 24 件とも 0 バイトだったことを確かめた。
- 手で直した文書:
  - bigquery-mcp の AGENTS.md: Quick Reference の `bd sync` の行を消して注意書きを足した。終了手順の「`bd sync` を実行する」を、「`.beads/issues.jsonl` が commit に入っていることを確かめる（自動で書き出され `git add` される）」にした。
  - website2026 の AGENTS.md（日本語）: `bd sync` の行を消し、自動で書き出されることと、`bd sync` / `bd dolt push` / `bd dolt remote add` を実行しないことを箇条書きで足した。
  - goto-goto の CLAUDE.md（日本語）: `bd onboard` を `bd prime` に替えた。`bd sync`、`bd sync --full`、`--flush-only` の説明を消し、自動で書き出されることと、実行しないコマンドを書いた。「bd は 0.49.0 を使っている … goto-3ol で管理する」を「bd は 1.3.2 を使っている。… 勝手にバージョンを上げない」にした。

### PATH の切り替え（2026-10-25）
- `C:\Users\yoichiro\go\bin\bd.exe` を 1.3.2 で上書きした。SHA-256 は `280517091DDA…46E2` で、`C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe` と同じ。
- 古い 0.49.0（dev）は `backup/2026-10-25/bin/bd.exe` にある（SHA-256 `4964C96B…7DCD`）。
- `Get-Command bd -All` で PATH 上の bd は 1 つだけ。`bd version` は `bd version 1.3.2 (9b65b9e19: HEAD@9b65b9e198ac)`。

### 検証（ステップ 5、2026-10-25）
[../scripts/verify-all.ps1](../scripts/verify-all.ps1) で、PATH 上の bd を使って 24 件を確かめた。結果: [verify_2026-10-25.csv](verify_2026-10-25.csv)
- **`bd list --all` の件数が、24 件すべてでリハーサルの移行後の件数と一致した**（合計 1,441 件）。
- `bd ready` は 24 件すべてで動いた。
- 実際に使われる hooks のフォルダに、bd の hooks は残っていない。
- `.beads` に未コミットの変更が残っているのは sql_viz_202604_old だけ。もとから git の管理外だったファイル（`.beads/config.yaml` など）が表示されているだけ。

### 移行後にやったこと
- goto-goto の `goto-3ol`（bd のアップグレードを管理していた issue）を閉じ、閉じた理由に結果を書いた。自動で書き出された `issues.jsonl` を commit した（`25aac2d`、main）。

### 気づいたこと: 利用統計の送信
- PATH の bd を初めてそのまま実行したとき、`Thanks for using bd! Quick heads-up: bd shares anonymous usage metrics` と出た。
- `bd metrics` の表示: `Anonymous usage metrics: ON`。送るのは、実行したコマンドの名前、bd の版、OS（端末から作った ID つき）。送り先は `https://gastownhall-eventsapi.com/mp/collect`。issue の中身、パス、remote、利用者は送らない、とある。
- 止めるには `bd metrics off`。止めるかどうかは利用者が決める（未決定）。

## 2 件目（calc_20260317）で分かったこと
- `.beads` の設定ファイルと AGENTS.md が git で管理されているリポジトリ。commit には `.beads` 以下の変更、`.gitignore`、AGENTS.md を含めた（`git add -u -- .beads .gitignore AGENTS.md`）。bd と関係のない変更（`.claude/settings.local.json` など）は含めていない。
- `.beads/interactions.jsonl`（0 バイト）は新しいストアにないので、削除として commit した。1.3.2 では `audit.enabled` が既定で無効なので、使われない。
- `.beads/config.yaml` は 1.3.2 の雛形に置き換わり、末尾に `export:` の 3 行（`auto: true`、`git-add: true`、`interval: 1s`）が入る。
- **本物の issue への書き込みで、自動の書き出しを確かめた**（[../scripts/check-auto-export.ps1](../scripts/check-auto-export.ps1)）。closed の `calc_20260317-jfg` の notes に 1 行を追記（`--append-notes`）したところ、`issues.jsonl` が書き換わり、追記が入り、`git add` された。この追記も同じ commit に含めた。
- 書き込むたびに `beads: repair: bd dolt remote add origin git+ssh://git@github.com/yo16/calc_20260317.git && bd dolt push` が出る（AGENTS.md で止めている）。

## 1 件目（sql_viz_202604_old）で分かったこと
- **1.3.2 は、git の設定に `beads.role` がないと、コマンドのたびに警告を出す**（`warning: beads.role not configured (GH#2950).`）。作業用のコピーでは `bd init --non-interactive` が設定していたので、出ていなかった。
  → `migrate-repo.ps1` で、入れ替えたあとに `git config beads.role maintainer` を入れるようにした（`.git/config` に入るので commit されない）。
  この警告が JSON の出力の前に混ざって、確認の段階で止まった。bd の出力を読むときは、標準エラーを分けて扱うように直し、確認だけをやり直した（`-ResumeVerify`）。入れ替えはその前に済んでいた。
- **このリポジトリでは、AGENTS.md、CLAUDE.md、`.beads` の設定ファイルが git の管理外だった**（管理されているのは `.beads/issues.jsonl` と `.gitignore` だけ）。ほかに、bd と関係のない未コミットの変更（`package.json` など）もあった。
  → commit するのは、もとから git で管理されているファイルのうち、移行で変わったものだけにした。AGENTS.md は直したが commit していない。
- `issues.jsonl` は 1.3.2 の書式になる（`_type` が付く、日時が UTC、並び順が変わる）。そのため差分は全行になる。中身は確認の段階で一致を確かめている。
- `bd prime` の出力（1.3.2）には `bd sync` や `bd dolt push` の指示はない。ただし「MEMORY.md を使うな」「TodoWrite を使うな」など強い指示を含む。
  → AGENTS.md では `bd prime` を案内しつつ、「このファイルと CLAUDE.md の決まりが優先する」と添えた。
- 自動の書き出しの警告の「修理の案内」は、具体的な URL つきのコマンドになる:
  `bd dolt remote add origin git+ssh://git@github.com/yo16/sql_viz_202604.git && bd dolt push`
  AGENTS.md に、これを実行しないよう書いた。

## AGENTS.md の書き換え（テンプレートの 3 か所）
- `Run \`bd onboard\` to get started.` → `Run \`bd prime\` to get started (the rules in this file and CLAUDE.md take precedence over its output).`
- Quick Reference から `bd sync               # Sync with git` を消し、その下に次の 2 段落を足した:
  - `` `.beads/issues.jsonl` is written and `git add`-ed automatically after every bd write (`export.auto`), so there is no separate sync step. ``
  - `` **Do not** run `bd sync`, `bd dolt push`, or `bd dolt remote add`: this project intentionally has no Dolt remote. Ignore the warning `beads: auto-export warning: no Dolt remote configured.` and the "repair" command it prints. ``
- Landing the Plane の `git pull --rebase` / `bd sync` / `git push` から `bd sync` を消した。
