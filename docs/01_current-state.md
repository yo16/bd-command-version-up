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

## 公式のアップグレード手順書（v1.3.2）から分かったこと
確認日: 2026-10-25。写し: [../references/upgrading_v1.3.2_2026-10-25.md](../references/upgrading_v1.3.2_2026-10-25.md)
（`gh api "repos/gastownhall/beads/contents/docs/getting-started/upgrading.md?ref=v1.3.2"`）

### 公式に推奨されている経路
- 手順書の「Cross-era Upgrades」節では、`.beads` の中身の構成で経路が決まる。
  `.beads/*.db` が 1 つだけある構成（SQLite 時代）は **「Sealed SQLite bridge」** を使う。
- 新しい bd は古い SQLite / 古い Dolt の構成を**開く前に拒否する**（データは書き換えない）。
- 上の「経路の候補」の 1（途中の版の自動移行）と 2（`bd migrate legacy-sqlite`）は、この手順書では推奨されていない。
  推奨は、次のスクリプトで移行先を別フォルダに作る方式。

```bash
scripts/migrate-legacy-to-current.sh \
  --source /absolute/path/to/old-project \
  --destination /absolute/path/to/old-project-cutover \
  --source-version v0.49.0 \
  --old-bd /absolute/path/to/verified-old-bd \
  --canonicalizer-bd /absolute/path/to/verified-v0.49.6-bd \
  --new-bd /absolute/path/to/current-bd \
  --prefix <issue の接頭辞>
```

### 途中の版が必要か
- 本体を途中の版に上げる必要はない。
- ただし、移行スクリプトの実行には次の 3 つの bd が必要になる。
  - 旧版: 公式リリースから取った v0.49.0。今入っている bd は `go install` の dev ビルドなので、そのままでは使えない可能性がある
  - **v0.49.6**: v0.49.6 より古い元データには、整形用（canonicalizer）として必須
  - 新版: v1.3.2
- 旧版のバイナリは公式リリース（`gastownhall/beads`）から取り、`checksums.txt` の SHA-256 で確かめる。
- スクリプトは bash と `jq` が必要で、**ソースの checkout から実行する**（インストール済みのバイナリには入っていない）。
  実行した commit を `git rev-parse HEAD` で記録しておく。
- スクリプトは元データの封印コピーを残し、新旧の export を比べて検証する。切り替えは、残された成果物を確認してから手で行う。

### 複数クローンの扱い
- 注意が必要なのは、**Dolt の remote を共有する複数クローン**の場合。1 台だけが移行して push し、ほかのクローンは `bd bootstrap` で取り込む。各クローンで別々に移行すると、スキーマが分岐して戻せなくなる。
- 今の版は SQLite なので Dolt の remote はまだない。
  ただし、**同じリポジトリを別の PC でも使っているか**は確かめておく。使っているなら、移行を担当する PC を 1 台に決める。

### アップグレード前に必ずやること
- **今の版の bd で**バックアップを取る（新しい版を入れたあとの export は、移行後のデータになってしまう）。
  - `bd export --all -o .beads/backup/pre-migrate-YYYYMMDD.jsonl`（0.49.0 に `--all` があるかは未確認）
  - bd を動かしていない状態で `.beads` フォルダを丸ごとコピーする
- 元データに書き込むプロセス（bd daemon、エディタ連携など）をすべて止める。

### アップグレード後にやること
- `bd upgrade review`（既定値が変わったコマンドがあるので、最初に作業する前に読む）
- `bd hooks install`（古い hooks のままだと安全のための修正が効かない）
- `bd version`、`bd doctor`

### Windows での入手方法（手順書の表より）
- PowerShell のインストーラー: `irm https://raw.githubusercontent.com/gastownhall/beads/main/install.ps1 | iex`
- `go install` を続ける場合: 組み込みモード（embedded）を使うには `CGO_ENABLED=1 GOFLAGS=-tags=gms_pure_go` が必要（C コンパイラーが要る）。
  `CGO_ENABLED=0` で作るとサーバーモード専用になる。

## bd daemon の状態
確認日: 2026-10-25。調べ方: `Get-Process bd`、各 `.beads` の `daemon.pid` に書かれた PID を `Get-Process -Id` で照合。
`bd daemon list` は `.beads` の外では `no beads database found` で動かない（`bd init` はしないこと）。

- **動いている daemon はない**（24 か所とも PID のプロセスは存在しない。`bd` / `dolt` という名前のプロセスもない）。
- 24 か所すべてに `daemon.lock` と `daemon.log` が残っている。21 か所には `bd.sock` と `daemon.pid` も残っている（calc_20260306、kakeizu、keihi_track には pid とソケットがない）。
- `daemon.lock` の中身は JSON で、DB の場所と bd の版が書かれている。例（qr_code_create）:
  `"database": "...\\.beads\\beads.db"`、`"version": "0.49.0"`、`"started_at": "2026-10-24T14:22:34Z"`
- 2026-10-24〜25 にも daemon が起動された記録がある（qr_code_create、smallpiece2024 の 4 件）。0.49.0 の bd は普通のコマンドを実行しただけで daemon を自動で起動する。
  → **バックアップと移行の作業中は、`--no-daemon` を付けるか環境変数 `BEADS_NO_DAEMON=1` を設定する**（環境変数の名前は 0.49.0 で確認する）。作業前に、そのリポジトリで Claude Code などが bd を使っていないことも確かめる。

## 公式の移行スクリプトが Windows で使えるか
確認日: 2026-10-25。スクリプトの写し: [../references/migrate-legacy-to-current_v1.3.2_2026-10-25.sh](../references/migrate-legacy-to-current_v1.3.2_2026-10-25.sh)（402 行、全体を読んだ）

### 公式リリースのバイナリ（`gh release view <版> --repo gastownhall/beads`）
| 版 | 公開日 | Windows 用 | checksums.txt |
|---|---|---|---|
| v0.49.0 | 2026-01-22 | `beads_0.49.0_windows_amd64.zip`（42,367,899 バイト） | あり |
| v0.49.6 | 2026-02-08 | `beads_0.49.6_windows_amd64.zip`（12,456,322 バイト） | あり |
| v1.3.2 | 2026-10-24 | `beads_1.3.2_windows_amd64.zip`（54,179,617 バイト） | あり |

v0.49.0 の Windows 用 zip だけほかの版より極端に大きい（同じ版の linux_amd64 は 11.7MB）。理由は未確認。

### この PC の道具（Git Bash）
- `bash`、`sha256sum`、`shasum`、`git`: あり
- **`jq`: なし**（スクリプトの必須条件。入れる必要がある）
- WSL: `C:\Program Files\WSL` が PATH にある（使えるかは未確認）

### 重要: スクリプトは v0.49.0 を受け付けない
`classify_source_version`（107〜117 行）が受け付ける元の版は **v0.9.1、v0.17.0、v0.49.6、v0.50.3 の 4 つだけ**。
それ以外は `source version is not one of the authenticated SQLite releases` で止まる。

| 元の版 | 方式 | 中でしていること |
|---|---|---|
| v0.9.1 | materialize-and-canonicalize | 旧版で JSONL を書き出し、v0.49.6 で init と export |
| v0.17.0 | canonicalize | 封印コピーを v0.49.6 で開いて（`init --force`）export |
| v0.49.6 / v0.50.3 | direct | 新版の `bd migrate legacy-sqlite` で封印コピーの DB から直接 JSONL を取り出す |

- 手順書には「v0.49.6 より古いものは `--canonicalizer-bd` を足す」とある。しかし実際のスクリプトでは、v0.49.0 はその前の版の判定で拒否される。**手順書とスクリプトが食い違っている**。
- 考えられる進め方（ステップ 3 で決める）:
  1. `.beads` の**コピー**を v0.49.6 で開いて SQLite のスキーマを 0.49.6 に上げ、そのコピーを元にして `--source-version v0.49.6`（direct）でスクリプトを通す
  2. スクリプトを使わず、canonicalize と同じ手順（v0.49.6 で export → 1.3.2 で `init --from-jsonl` → export して比べる）を手で行う
  3. 1.3.2 の `bd migrate legacy-sqlite` が 0.49.0 の DB を直接読めるか、コピーで試す

### Windows（Git Bash）で問題になりそうな箇所
| 箇所 | 内容 | 影響 |
|---|---|---|
| 245 行 | `jq` が必須 | 入れないと動かない |
| 314〜328 行 `run_at` | `env -i` で環境変数を全部消し、`PATH` と `HOME` などだけを渡して bd を動かす | Windows の Go プログラムはホームの場所を `USERPROFILE` から取る。`SYSTEMROOT`、`TEMP`、`APPDATA` などもなくなるので、bd が設定やキャッシュの場所を決められずに失敗するおそれがある。**一番危ない箇所** |
| 322 行 | `GIT_CONFIG_GLOBAL=/dev/null` | Git for Windows は `/dev/null` を扱えるはずだが、未確認 |
| 352〜355、379、384 行 | `/d/...` 形式のパスを bd.exe に渡す | Git Bash（MSYS）が自動で `D:/...` に直すので、たぶん動く |
| 297〜305 行 `fingerprint` | `.beads` の全ファイルのハッシュを前後で比べる | 元の `.beads` に誰かが書き込むと止まる（daemon の自動起動に注意） |

`cp -Rp`、`find`、`dd`、`cmp`、プロセス置換（`<(...)`）は Git Bash にもある。
WSL で Linux 用のバイナリを使って動かせば、Windows 特有の問題はほぼ避けられる（`/mnt/d/...` のコピーを扱う）。

## 公式バイナリの入手と確認
確認日: 2026-10-25

### 入手と検証
- `gh release download <版> --repo gastownhall/beads -p "beads_<版>_windows_amd64.zip" -p checksums.txt -D work/downloads/<版>`
  （`work/` は `.gitignore` で除外。ダウンロードした zip と checksums.txt はここに残す）
- SHA-256 は 3 つとも `checksums.txt` と一致した。

| 版 | zip の SHA-256 | 展開先 | `bd version` |
|---|---|---|---|
| v0.49.0 | `ba849f6a720fb57aaeddcf624cc72303b50cb4c8904de78403fc2be35d78f0a9` | `C:\Users\yoichiro\beads-bin\v0.49.0\bd.exe`（119,327,232 バイト） | `bd version 0.49.0 (b5178e18: HEAD@b5178e1895e7)` |
| v0.49.6 | `b89c275160a51b5bc7e3a4faae8f0db6c1b850c908234779c0b783526f1c21df` | `C:\Users\yoichiro\beads-bin\v0.49.6\bd.exe`（35,132,928 バイト） | `bd version 0.49.6 (c064f2aa: HEAD@c064f2aa9981)` |
| v1.3.2 | `e59cb7742278185493e30c2eb97cb318db8d7a58c28ee5e88c2a30c7630c0975` | `C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe`（156,987,392 バイト） | `bd version 1.3.2 (9b65b9e19: HEAD@9b65b9e198ac)` |

- どれも PATH には入れていない。PATH 上の bd は今までどおり `C:\Users\yoichiro\go\bin\bd.exe`（0.49.0 dev）。
- **Windows で入手するには、公式の zip で足りる。** 展開するだけで動き、`go install` や CGO の準備は要らない。
- 公式スクリプトは `bd version` の出力から版を確かめる（119〜130 行）。上の出力は、どれもその判定を通る形になっている。

### 1.3.2 のコマンドで分かったこと（`--help` のみ実行）
- `bd daemon` はなくなっている。
- `bd migrate legacy-sqlite --source-db PATH --output PATH|-` がある。説明は「Read an authenticated legacy SQLite database as JSONL」（source は読み取り専用で開く）。
- `bd migrate hooks --dry-run | --apply` がある。古い hooks を新しい形式（marker-managed）に移す計画を作り、適用する。
- `bd hooks install | uninstall | list | run` がある。新しい hooks は `bd hooks run` を呼ぶ thin shim になっている。
- **`bd sync` の意味が変わった。** 0.49.0 では JSONL への書き出しだったが、1.3.2 では「Dolt の remote と pull / push する」コマンドになった。
  `--flush-only` というオプションはない。Dolt の remote がなければ、**git の origin を Dolt の remote として自動で採用する**動きもある。

### 古い hooks と新しい版の組み合わせ
今の hooks（[02_targets.md](02_targets.md) の pm, pc）は、PATH 上の `bd` を呼ぶ。
- pre-commit: `bd sync --flush-only` が失敗すると **exit 1 で commit を止める**。
- post-merge: `bd import -i .beads/issues.jsonl` を呼ぶ。失敗しても警告だけで、止めない。

起こりうること:
1. PATH の bd を 1.3.2 に替えた時点で、まだ移行していないリポジトリは開けなくなる。bd の hooks がある 18 か所では、`--flush-only` がないために commit も止まるとみられる。
2. 移行が済んだリポジトリでも、PATH の bd が 0.49.0 のままなら、0.49.0 は新しい Dolt のストアを読めない。hooks が失敗して commit が止まるとみられる。
3. 新しい hooks（`bd hooks run` を呼ぶ shim）を入れても、PATH の bd が 0.49.0 なら `hooks run` がないので動かない。

→ **PATH の bd を替えることと、各リポジトリの hooks を入れ替えることは、同じ時期にまとめて行う必要がある。**
ステップ 3 で、順番（全件の移行を一気に済ませるか、移行中は hooks を一時的に外すか）を決める。
上の 1〜3 は推測で、試験移行（4a）で実際に確かめる。

## 試し: 1.3.2 は 0.49.0 の DB を直接読めるか
確認日: 2026-10-25。スクリプト: [../scripts/trial-legacy-sqlite.ps1](../scripts/trial-legacy-sqlite.ps1)

- 対象: sql_viz_202604_old の `.beads` を `work/trial/sql_viz_202604_old/.beads` にコピーし、そのコピーで試した。
- 実行したコマンド（空のフォルダ `probe` から。`BD_DISABLE_METRICS=1`、`BD_NON_INTERACTIVE=1` を設定）:
  `bd(1.3.2) -C probe migrate legacy-sqlite --source-db <コピー>\beads.db --output legacy-export.jsonl`
- 結果: **`Error: unsupported legacy SQLite release "0.49.0"`（exit 1）。読めない。**
- コピーと元の `.beads` は、実行の前後でハッシュが同じ（`AAE50F15…D9517`）。`probe` にもファイルはできなかった。
- 公式スクリプトが受け付ける版（v0.49.6 / v0.50.3 だけが direct）と同じ制限が、bd 本体にもある。
  → 「経路の候補」の 3（1.3.2 で直接読む）は**使えない**。
  残るのは、**v0.49.6 で一度開いて 0.49.6 の DB にしてから 1.3.2 で読む**方法（候補 1 と 2）。

## 試し: v0.49.6 で開き直してから 1.3.2 で読む
確認日: 2026-10-25。スクリプト: [../scripts/trial-canonicalize.ps1](../scripts/trial-canonicalize.ps1)（対象は sql_viz_202604_old のコピー）

### 手順と結果
1. `.beads` を `work/trial/sql_viz_202604_old-v0496-2/sealed-source/.beads` にコピーし、`sealed-source` で `git init` した（公式スクリプトと同じ）。
2. v0.49.6 で `bd --no-daemon --no-auto-import init --force --prefix sql_viz_202604` を実行した → exit 0。
   - **DB の `bd_version` は 0.49.0 から 0.49.6 に変わり、件数は 27 件（closed 27）のままだった。**
   - `sealed-source` の直下に `AGENTS.md` と `.gitattributes` ができた。本物のリポジトリでこのコマンドを実行してはいけない。
3. 1.3.2 で `bd migrate legacy-sqlite` を実行した → **`Error: legacy SQLite schema drift in issues`（exit 1）**。
   - なお、`-C probe` を付けて実行すると `no beads project found` で拒否される。cd してから実行する（公式スクリプトもそうしている）。
4. 元の `.beads` のハッシュは、最後まで変わらなかった。

### schema drift の正体
作業用のフォルダで 0.49.6 の新しい DB を作り（`work/trial/fresh-0496`）、開き直した DB と比べた。
- issues テーブルの 57 列は、名前・型・既定値がすべて同じ。dependencies、labels、comments、events も同じ。
- 違うのは**列の並び順**だけ。0.49.0 から上げた DB では、あとから足された列（`spec_id`、`wisp_type`、`metadata` など）が末尾に `ALTER TABLE` で追加されている。新しく作った 0.49.6 の DB では、それらは途中に並んでいる（cid 19 以降がずれる）。
- 1.3.2 の `legacy-sqlite` は、列の並び順まで含めて本物の 0.49.6 / 0.50.3 と同じ形かを確かめているとみられる。

### 分かったこと
- 0.49.0 から始める場合、`legacy-sqlite`（公式スクリプトの direct 方式）は使えない。
- 公式スクリプトの **canonicalize 方式**（v0.49.6 で `init --force` → **v0.49.6 で JSONL を export** → 1.3.2 で `init --from-jsonl` → 1.3.2 で export して比べる）は、`legacy-sqlite` を使わないので、この問題に当たらない。これを本命の経路とする。

## 試し: canonicalize 方式を最後まで通す（成功）
確認日: 2026-10-25。スクリプト: [../scripts/trial-cutover.ps1](../scripts/trial-cutover.ps1)（対象は sql_viz_202604_old のコピー）

公式スクリプトの canonicalize 方式を PowerShell で書き直した。`env -i` は使わず、公式スクリプトが設定する環境変数（`BD_DISABLE_METRICS`、`BEADS_NO_DAEMON` など）だけを足した。

| 手順 | 実行した場所 | コマンド | 結果 |
|---|---|---|---|
| 1 | `sealed-source`（git init 済み、`.beads` のコピー） | v0.49.6 `--no-daemon --no-auto-import init --force --quiet --prefix sql_viz_202604` | exit 0 |
| 2 | 同上 | v0.49.6 `--no-daemon --no-auto-import export --format jsonl -o export.jsonl` | exit 0、27 件 |
| 3 | `cutover`（git init 済み、`.beads/issues.jsonl` だけを置く） | v1.3.2 `init --from-jsonl --quiet --non-interactive --skip-hooks --skip-agents --prefix sql_viz_202604` | exit 0 |
| 4 | 同上 | v1.3.2 `export --all -o candidate-export.jsonl` | `Exported 27 issues`、exit 0 |

- cutover の `.beads/metadata.json` は `{"database":"dolt","backend":"dolt","dolt_mode":"embedded","dolt_database":"sql_viz_202604",...}`。`embeddeddolt/` ができた。
- 突き合わせ（id ごとに status、title、ラベル数、依存数、コメント数）:
  - 元の DB → v0.49.6 の export: 27 / 27、抜け 0、余分 0、違い 0
  - v0.49.6 の export → v1.3.2 の export: 27 / 27、抜け 0、余分 0、違い 0
  - 元の DB → v1.3.2 の export: 27 / 27、抜け 0、余分 0、違い 0
- 元の `.beads` のハッシュは最後まで変わらなかった。

### この試しで確かめられていないこと
- このリポジトリには**ラベルとコメントが 0 件**しかない（依存は 17 件あり、一致した）。ラベルとコメントは、それらがあるリポジトリで確かめる必要がある。
- 比べたのは上の 5 項目だけ。説明文、優先度、日時などは比べていない。公式スクリプトは全項目を正規化して比べている（`normalize_export`、132〜183 行）。
- **events（変更の履歴）は引き継がれない。** このリポジトリの DB には 71 件ある。`bd export` は issue だけを書き出すもので（手順書の「`bd export` captures issues, not Dolt history or config」）、移行後の DB には issue ごとの変更履歴が残らない。元の `.beads` のバックアップには残る。
- DB に入っている設定（`config` テーブル。issue_prefix 以外のもの）も引き継がれないとみられる。

## 不具合: 1.3.2 の取り込みで closed_at などが 9 時間ずれる
確認日: 2026-10-25

### 見つけた経緯
`trial-cutover.ps1` の比較を全項目に広げ、公式スクリプトの `normalize_export` と同じ規則にしたところ、sql_viz_202604_old で次の 2 つがずれていた。
- `closed_at`: 27 件すべて
- 依存関係の `created_at`: 依存のある 13 件

例（sql_viz_202604-09j）:

| 項目 | 元の DB / v0.49.6 の export | 1.3.2 の export（`bd show --json` でも同じ） | 正しい UTC |
|---|---|---|---|
| created_at | `2026-04-05T10:35:04.8098208+09:00` | `2026-04-05T01:35:05Z` | 正しい |
| updated_at | `2026-04-05T11:51:42.0008201+09:00` | `2026-04-05T02:51:42Z` | 正しい |
| closed_at | `2026-04-05T11:51:42.0008201+09:00` | `2026-04-05T11:51:42Z` | **誤り**（正しくは `02:51:42Z`） |
| 依存の created_at | `2026-04-05T10:38:01.1499785+09:00` | `2026-04-05T10:38:01Z` | **誤り**（正しくは `01:38:01Z`） |

日本時間の時刻の数字はそのままで、`+09:00` が `Z` に付け替えられている。その結果、9 時間未来にずれる。
件数やタイトルでは気づけない。

### 上流の状況
- [gastownhall/beads#5765](https://github.com/gastownhall/beads/issues/5765)「bd import / init --from-jsonl: closed_at loses its UTC offset」。0.49.1 から 1.2.1 への移行で報告されたもので、内容は同じ。
- 修正は commit `e8839c4`（PR #5771「fix(import): normalize optional timestamps to UTC on insert」、2026-09-30）。
- しかし **v1.3.2 にはこの修正が入っていない**。`gh api repos/gastownhall/beads/compare/v1.3.2...e8839c4` の結果は `diverged`（ahead 243、behind 75）で、v1.3.2 は修正を含まない枝から出ている。
- #5765 によると、入力が UTC（`Z`）なら正しく入る。

### 回避策
取り込む前に、JSONL の日時の項目（`created_at`、`updated_at`、`started_at`、`closed_at`、`due_at`、`defer_until`、`compacted_at`、`last_activity`、`deleted_at`。依存とコメントの中の `created_at` も含む）を、**同じ時刻の UTC 表記に書き換える**。
例: `2026-04-05T11:51:42.0008201+09:00` → `2026-04-05T02:51:42.0008201Z`

- 書き換えるのは、上の名前の項目の値だけ。行のほかの部分はバイト単位で同じに保つ。説明文の中にある `\"closed_at\"` は、直前が `\` なので対象にならない。
- 実装: `trial-cutover.ps1` の `Convert-JsonlToUtc`
- sql_viz_202604_old で試した結果: 日時 98 個（27 件 × 3 項目 + 依存 17 件）を書き換えた。書き換える前の v0.49.6 の export と、1.3.2 の export を全項目で比べ、**違いは 0**。

## 決めたこと
- **events（変更の履歴）は引き継がない。** 移行できないものは仕方がない（2026-10-25、利用者の判断）。元の `.beads` はバックアップとして丸ごと残す。

## 未確認（次にやること）
- [x] 公式の `docs/getting-started/upgrading.md`（v1.3.2）を読む（2026-10-25、上の節に記録）
- [ ] 各 `.beads` の構成が本当に「`*.db` が 1 つ」か（棚卸しで確認）
- [ ] 0.49.0 の `bd export` に `--all` があるか
- [x] v0.49.0 / v0.49.6 の公式リリースに Windows 用のバイナリがあるか。移行スクリプトが Git Bash で動くか、`jq` は入っているか（2026-10-25、上の節に記録。バイナリはある、jq はない、スクリプトは v0.49.0 を拒否する）
- [ ] 今の dev ビルドと公式の v0.49.0 で、DB のスキーマが同じか
- [ ] WSL が使えるか（ディストリビューションが入っているか）
- [ ] 同じリポジトリを別の PC でも使っているか
- [ ] `docs/RECOVERY.md`、`docs/recovery/` の内容
- [ ] 1.3.0 の「v1.2.2 users 向け Breaking changes」と CHANGELOG `[1.2.1]` 節の要点
- [ ] 1.3.2 の migration 0059 の注意書きの全文
- [x] Windows での入手方法（2026-10-25、公式の zip で動く。上の「公式バイナリの入手と確認」に記録）
- [x] 1.3.2 の `bd migrate legacy-sqlite` が 0.49.0 の DB を読めるか（2026-10-25、読めない。上の「試し」に記録）
- [x] コピーを v0.49.6 で開くと、DB の `bd_version` が 0.49.6 になり、1.3.2 で読めるようになるか（2026-10-25、版は 0.49.6 になるが、列の並び順の違いで `legacy-sqlite` は拒否する）
- [x] canonicalize 方式（v0.49.6 で export → 1.3.2 で `init --from-jsonl`）で、issue が 1 件ずつ一致するか（2026-10-25、sql_viz_202604_old で 27 件すべて一致。ラベルとコメントは未確認）
- [x] 全項目（説明文、日時、コメントの本文、ラベルの名前）まで一致するか。ラベルやコメントのあるリポジトリでも通るか（2026-10-25、24 か所すべて一致。[03_rehearsal.md](03_rehearsal.md)）
- [x] events（変更の履歴）が引き継がれないことを受け入れるか（2026-10-25、受け入れる。「決めたこと」に記録）
- [ ] 古い hooks と新しい版を組み合わせたときに何が起きるか（試験移行で確かめる）
- [x] bd daemon が動いているか（2026-10-25、動いていない。上の節に記録）
- [ ] daemon の自動起動を止める方法（`--no-daemon`、環境変数）を 0.49.0 で確かめる
