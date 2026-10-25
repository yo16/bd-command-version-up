# 05 移行の記録

手順は [04_method.md](04_method.md)。1 件ずつ [../scripts/migrate-repo.ps1](../scripts/migrate-repo.ps1) で移行し、
エージェント向け文書は [../scripts/fix-agent-docs.ps1](../scripts/fix-agent-docs.ps1) で直し、差分を見てから commit する（push はしない）。
作業フォルダは `work/cutover-2026-10-25/<ルート>__<リポジトリ>/`（`build/`、`replaced/.beads`（入れ替える前の .beads）、`migrate.json`、`build.log`）。

## 一覧
| # | リポジトリ | 日時 | 件数（元 → 1.3.2） | tombstone | hooks を外した | commit | 備考 |
|---|---|---|---|---|---|---|---|
| 1 | yo16/sql_viz_202604_old | 2026-10-25 | 27 → 27 | 0 | pre-commit, post-merge | `c9343d4`（dev） | 4a の 1 件目。下の「1 件目で分かったこと」 |
| 2 | yo16/calc_20260317 | 2026-10-25 | 18 → 18 | 0 | pre-commit, post-merge | `85ebfb6`（dev） | 4a の 2 件目。AGENTS.md も commit。本物の issue への書き込みで自動の書き出しを確認 |

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
