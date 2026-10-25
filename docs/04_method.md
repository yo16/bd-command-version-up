# 04 方式（本番の手順の案）

作成: 2026-10-25。**案**。「決めること」に答えが出たら確定する。

## 経路
[03_rehearsal.md](03_rehearsal.md) で 24 か所すべてのコピーで通した手順を、そのまま本番に使う。

1. `.beads` のコピーを v0.49.6 で `init --force` → `--allow-stale export`
2. 日時を UTC 表記にそろえる（上流 #5765 の回避）
3. 1.3.2 で `init --from-jsonl` → `export --all` → 突き合わせ
4. 突き合わせが通ったら、できた `.beads` を元のリポジトリの `.beads` と入れ替える

元のリポジトリの中では bd を実行しない。新しいストアは作業フォルダで作り、確かめてから入れ替える。

## この節を書く前に確かめたこと（2026-10-25、すべて作業用のコピーで実施）

### hooks と PATH の組み合わせ
[../scripts/trial-hooks.ps1](../scripts/trial-hooks.ps1) と [../scripts/trial-hook-commit.ps1](../scripts/trial-hook-commit.ps1) で、移行後のストアの上で空の commit を作って確かめた。

| hooks | PATH の bd | commit |
|---|---|---|
| 古い hooks（0.49.0 の pre-commit） | 0.49.0 | **止まる**（`Error: Failed to flush bd changes to JSONL`、exit 1） |
| 古い hooks | 1.3.2 | **止まる**（同上） |
| 新しい hooks（1.3.2 の `bd hooks install`） | 0.49.0 | 通る（警告だけ。0.49.0 にも `bd hooks run` がある） |
| 新しい hooks | 1.3.2 | 通る |

- **リポジトリを移行するときに、同時に hooks も入れ替えれば、PATH の bd がどちらの版でも commit は止まらない。**
- まだ移行していないリポジトリは、PATH を 1.3.2 に替えた時点で commit が止まる（古い hooks が 1.3.2 の `bd sync --flush-only` を呼ぶため。`--flush-only` は 1.3.2 にない）。
  → **PATH の切り替えは、全件の移行が終わってから行う。**
- `bd migrate hooks --dry-run` は、古い pre-commit / post-merge を「legacy_only → 管理された形式に変換」と判定した。`bd hooks install` は 5 種類（pre-commit、post-merge、pre-push、post-checkout、prepare-commit-msg）を入れる。
- 新しい hooks は薄いスクリプトで、PATH 上の `bd` の `bd hooks run <名前>` を呼ぶ。終了コード 3（DB が未初期化）と、タイムアウト（既定 300 秒）の場合は commit を止めない。

### 移行してから PATH を替えるまでの間
- 移行後のストアに 0.49.0 で `bd list` / `bd ready` を実行すると、`Error: failed to open database: dolt backend requires CGO` で終わる。ファイルは変わらない。
- この間は bd が使えない。エージェントがエラーのヒントに従って `bd init` などを実行しないよう、間はできるだけ短くする。

### ストアの移動
- [../scripts/trial-move-store.ps1](../scripts/trial-move-store.ps1): 作業フォルダで作った `.beads` を別の git リポジトリにコピーしても、69 件のまま読めた。`bd where` も新しい場所を指す。
- **embedded モードでは `bd doctor` が使えない**（`'bd doctor' is not yet supported in embedded mode`）。移行後の確認は、件数と export の突き合わせで行う。

### 移行後の `.beads` の中身
- 新しくできるもの: `embeddeddolt/`（データ本体）、`metadata.json`、`config.yaml`、`README.md`、`.gitignore`、`.local_version`、`*.gate.lock`
- 新しい `.beads/.gitignore` は `embeddeddolt/`、`*.db`、`daemon.*`、`*.lock`、`sync-state.json` などを除外する。git で管理されるのは `metadata.json`、`config.yaml`、`README.md`、`.gitignore`、（あれば）`issues.jsonl`。
- **issue のデータ本体は git の管理から外れる。** 今は `issues.jsonl` が git に入っているので、issue の内容が git の履歴にも残っている。
- 1.3.2 の既定（[../references/configuration_v1.3.2_2026-10-25.md](../references/configuration_v1.3.2_2026-10-25.md) 123〜131 行）:
  - `export.auto: false`、`export.git-add: false`（JSONL は自動で更新されない）
  - `backup.enabled: false`、`backup.git-push: false`、`dolt.auto-push`: 既定で無効（勝手に push しない）

### export.auto と export.git-add（[../scripts/trial-export-auto.ps1](../scripts/trial-export-auto.ps1)、作業用のコピーで実施）
- `bd config set export.auto true` などの設定は `.beads/config.yaml` に書かれる（git で管理されるファイル）。
- **既定の `export.interval`（60 秒）だと、直前の export から 60 秒以内の書き込みは書き出されない。** 次に何かを書き込むまで JSONL に出ないので、そのまま commit すると最新の変更が git に入らない。
  `0s` を設定しても既定の 1 分として扱われた（`auto-export: throttled (last export 45s ago, interval 1m0s)`）。
- **`export.interval` を `1s` にすると、書き込むたびに JSONL を書き出し、`git add` までする**（`auto-export: wrote 26 issues ... (full, 749ms)`。git の状態は `M  .beads/issues.jsonl`）。
  → 各リポジトリで `export.auto true`、`export.git-add true`、`export.interval 1s` を設定する。
- 書き込むたびに、次の警告が標準エラーに出る:
  `beads: auto-export warning: no Dolt remote configured.`
  `beads: repair: add a git origin, then run 'bd dolt remote add origin <git-remote-url>' and 'bd dolt push'.`
  **エージェントがこの修理の案内に従うと、GitHub の origin に Dolt のデータを push してしまう。** AGENTS.md に、この警告は無視し、`bd dolt remote add`、`bd dolt push`、`bd sync` は実行しないと書く。

### エージェント向け文書（[agent-docs_2026-10-25.csv](agent-docs_2026-10-25.csv)、[../scripts/scan-agent-docs.ps1](../scripts/scan-agent-docs.ps1)）
- 24 か所中 20 か所の AGENTS.md が同じテンプレートでできている。その中に `bd onboard` が 1 回、`bd sync` が 2 回ある。
  `bd sync` は、作業を終えるときに必ず実行する手順（`git pull --rebase` → `bd sync` → `git push`）に入っている。
- goto-goto の CLAUDE.md には `bd sync --flush-only` などが書かれている。0.49.0 に固定する旨と、アップグレードを `goto-3ol` で管理している旨も書かれている。
- **1.3.2 の `bd sync` は、Dolt の remote と pull / push するコマンドになった。** Dolt の remote が未設定なら、git の origin を Dolt の remote として採用する動きがある（`--yes` で同意。同意がないときにどう動くかは未確認）。
  文書をそのままにすると、エージェントが作業の終わりに GitHub へ Dolt のデータを push しようとするおそれがある。

## 手順（案）

### 0. 前の準備
- 対象のリポジトリで作業しているエディタやエージェントを止める。bd と dolt のプロセスがないことを確かめる。
- 棚卸しをやり直して（[../scripts/inventory.ps1](../scripts/inventory.ps1)）、今日の数字から変わっていないかを見る。変わっていれば、その数字を基準にする。

### 3.5 バックアップ（2026-10-25 実施済み）
- 置き場所: **このリポジトリの `backup/2026-10-25/`**（`.gitignore` で除外）。`D:\beads-backup` は作らない（利用者の指示）。
- スクリプト: [../scripts/backup.ps1](../scripts/backup.ps1)。結果: [backup_2026-10-25.csv](backup_2026-10-25.csv)
- 中身:
  - `<ルート>\<リポジトリ>\.beads\`: `.beads` を丸ごとコピーしたもの
  - `<ルート>\<リポジトリ>\hooks\git-hooks\`: `.git\hooks` の `*.sample` 以外
  - `<ルート>\<リポジトリ>\hooks\core-hooksPath\`: `core.hooksPath` が別の場所を指す場合は、そこにあるもの
  - `<ルート>\<リポジトリ>\git-state.json`: ブランチ、HEAD、`core.hooksPath`、`.beads` の git status
  - `bin\bd.exe`: `C:\Users\yoichiro\go\bin\bd.exe`（`bd version 0.49.0 (dev)`、SHA-256 `4964C96B…7DCD`）
  - `manifest.csv`: コピーしたすべてのファイルについて、コピー元とコピー先の SHA-256
- 結果: **24 / 24 成功。ファイル 419 個で、ハッシュの不一致は 0。** コピーの前後で、コピー元の `.beads` は変わらなかった。合計 91 MB。
- 分かったこと: takatsu-connect-advisor（`core.hooksPath` は `.husky`）と sql_viz_202604_old（`core.hooksPath` は sql_viz_202604 の `.git\hooks`）にも、`.git\hooks` に bd の hooks が残っている。どちらも使われていない。

### 4a. 試験移行（1〜2 件）
- 対象: sql_viz_202604_old（使っていない。27 件）。もう 1 件は calc_20260317（18 件、全件 closed）。
- 1 件ずつ次を行う:
  1. 作業フォルダで新しいストアを作り、突き合わせる（リハーサルと同じ）
  2. 元の `.beads` を `.beads.pre-1.3.2` に名前を変えてから、すぐにバックアップの場所へ動かす（リポジトリの中に古いものを残さない）
  3. 新しい `.beads` を置く。`issues.jsonl` は新しいストアから export し直したものにする
  4. hooks を入れ替える（「決めること」の 2）
  5. 1.3.2 で、件数と export の突き合わせをもう一度行う（元の DB と比べる）
  6. 空の commit で hooks を確かめる（commit は作らずに `git commit --dry-run` で済むか、4a で確かめる）
  7. git の差分を確認する（「決めること」の 1、3）
- PATH の bd はこの時点ではまだ 0.49.0。試験の対象では、1.3.2 をフルパスで呼ぶ。

### 4b. 本番移行（残り）
- 4a と同じ手順を、スクリプトで 1 件ずつ実行する。1 件 20 秒前後なので、残り 22 件は 10 分程度で終わる見込み。
- 1 件でも突き合わせが通らなければ、その場で止める。そのリポジトリは入れ替えずに元のまま残す。
- 全件が終わったら、すぐに PATH を切り替える:
  - `C:\Users\yoichiro\go\bin\bd.exe` を 1.3.2 の `bd.exe` に置き換える。古いものはバックアップに残す。
  - PATH に bd が 1 つだけあることを確かめる（2 つあると `Warning: multiple 'bd' binaries found in PATH` が出る）。

### 5. 検証
- 全リポジトリで、`bd list --all --json` の件数が、棚卸しの件数から tombstone を引いた数と一致する。
- `bd ready` が動く。
- 空の commit で hooks を確かめる。
- `bd upgrade review` を 1 回読み、既定値が変わったコマンドを確かめる。

### 戻し方（リポジトリごと）
1. 新しい `.beads` を消す（`embeddeddolt/` ごと）。
2. バックアップ（`backup/2026-10-25/<ルート>/<リポジトリ>/.beads`）を元の場所へ戻し、SHA-256 が `manifest.csv` と一致することを確かめる。
3. バックアップの hooks を `.git\hooks` に戻す。
4. PATH を切り替えた後なら、`go\bin\bd.exe` を 0.49.0 に戻す（ほかのリポジトリも戻すことになる）。

## 決めたこと（2026-10-25、利用者の回答）
1. `issues.jsonl` を git で**管理し続ける**。各リポジトリで `export.auto` と `export.git-add` を有効にする。
2. bd の hooks は**外す**。
3. 各リポジトリでの commit は **Claude が行う**。push は利用者が確認してから行う。
4. エージェント向け文書（AGENTS.md、CLAUDE.md）は**直す**。

まだ決めていないもの（既定の案のまま進め、変えるときは指示をもらう）:
- 5. 対象から外すリポジトリ → 外さない（24 か所すべて移行する）
- 6. バックアップの置き場所 → このリポジトリの `backup/`（gitignore）。利用者の指示（2026-10-25）
- feature ブランチの上にある 3 か所 → 今のブランチに commit する。利用者の了承済み（2026-10-25）

## 決めること（検討時の選択肢。記録のために残す）
1. **`issues.jsonl` を git で管理し続けるか**
   - 案 A（おすすめ）: 続ける。各リポジトリで `bd config set export.auto true` と `bd config set export.git-add true` を設定し、書き込むたびに JSONL を更新させる。今と同じく issue の内容が git の履歴に残り、GitHub でも見える。
   - 案 B: やめる。データは Dolt のストアだけに置く（git には入らない。この PC が壊れると消える）。バックアップは `bd backup init` で別の場所へ取る。
2. **hooks をどうするか**
   - 案 A（おすすめ）: bd の hooks を外す（`bd hooks uninstall`、または古い 2 本を消す）。案 1-A なら JSONL の更新は書き込み時に行われるので、hooks は要らない。PATH の版にも左右されない。
   - 案 B: 1.3.2 の hooks を入れる（`bd migrate hooks --apply` または `bd hooks install`）。pre-push などの中身が何をするかは、まだ確かめていない。
3. **各リポジトリでの commit と push を誰が行うか**
   - 移行後、各リポジトリには `.beads/` の差分（新しい `.gitignore`、`config.yaml`、`metadata.json`、`issues.jsonl` など）ができる。
   - 案 A: 私が各リポジトリで commit する。push はしない（利用者が確認してから行う）。
   - 案 B: commit も利用者が行う。
   - feature ブランチの上にある 3 か所（simple-translator、sql_viz_202604、takatsu-connect-advisor）は、そのブランチに commit することになる。先に既定のブランチに切り替えるかどうかも決める。
   - `.beads` に未コミットの変更がある 7 か所は、移行後の `issues.jsonl` に変更が含まれる（DB から作り直すため）。先に commit しておく必要はない。
4. **エージェント向け文書（AGENTS.md、CLAUDE.md）を直すか**
   - 案 A（おすすめ）: 直す。`bd sync` を、案 1-A なら手順から外す（JSONL は自動で更新される）。案 1-B なら `bd export` に置き換える。`bd onboard` は `bd prime` に置き換える。goto-goto の「0.49.0 に固定」の記述も直す。直した文書も、決めること 3 と同じ扱いで commit する。
   - 案 B: 直さない（利用者が直す）。
5. **対象から外すリポジトリがあるか**
   - たとえば sql_viz_202604_old、sql_viz_202604_3 のように使っていないもの。外したものは、PATH を替えた後に bd で開けなくなる（元の `.beads` はそのまま残る）。
6. **バックアップの置き場所**: 案は `D:\beads-backup\`。

## 移行後にやること
- goto-goto の issue `goto-3ol`（bd のアップグレードを管理している）に結果を書き、閉じる。
- `C:\Users\yoichiro\beads-bin\` のバイナリと `work/` は、検証が済むまで残す。
