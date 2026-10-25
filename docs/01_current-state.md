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
- [ ] Windows での入手方法（`go install` を続けるか、リリースバイナリ / `install.ps1` にするか。新しい版は CGO が必要な可能性あり）
- [x] bd daemon が動いているか（2026-10-25、動いていない。上の節に記録）
- [ ] daemon の自動起動を止める方法（`--no-daemon`、環境変数）を 0.49.0 で確かめる
