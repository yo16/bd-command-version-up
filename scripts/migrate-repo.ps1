# 1 つのリポジトリの .beads を 1.3.2 に移行する（commit はしない）
#   1. .beads がバックアップを取ったときから変わっていないことを確かめる（docs/backup_2026-10-25.csv の TreeHash）
#   2. 作業フォルダで新しいストアを作り、突き合わせる（trial-cutover.ps1）
#   3. 新しいストアに export.auto / export.git-add / export.interval=1s を設定する
#   4. リポジトリの .beads を作業フォルダへ移し、新しい .beads を置く
#   5. 1.3.2 で .beads/issues.jsonl を書き出し直す
#   6. ルートの .gitignore に 1.3.2 の実行時ファイル（*.gate.lock* ほか）を足す
#   7. リポジトリ自身の .git/hooks から bd の hooks を消す（バックアップ済み）
#   8. リポジトリの git の設定（.git/config）に beads.role=maintainer を入れる（ないと 1.3.2 が毎回警告を出す）
#   9. リポジトリの中で、件数と中身をもう一度突き合わせる
# 作業フォルダ: <WorkRoot>\<ルート>__<リポジトリ>\（build、replaced、verify-export.jsonl、migrate.json）
# 使い方: pwsh -NoProfile -File scripts\migrate-repo.ps1 -Root yo16 -Repo sql_viz_202604_old -Prefix sql_viz_202604 -WorkRoot <work\cutover-日付>
#         -ResumeVerify: 入れ替えまで済んだ作業フォルダについて、8 と 9 だけをやり直す
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$WorkRoot,
    [switch]$ResumeVerify,
    [string]$BackupSummary = (Join-Path $PSScriptRoot '..\docs\backup_2026-10-25.csv'),
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'; $env:BEADS_DOLT_AUTO_START = '0'

function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
# 標準出力だけを返す（標準エラーの警告が JSON に混ざらないように）。失敗したときは標準エラーも含めて例外にする
function Invoke-Bd($dir, [string[]]$arguments) {
    Push-Location $dir
    try {
        $all = & $NewBd @arguments 2>&1
        $err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        $out = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        if ($LASTEXITCODE -ne 0) { throw "bd $($arguments -join ' ') failed (exit $LASTEXITCODE): $(($out + $err) -join ' ')" }
        if ($err) { $script:bdWarnings += $err }
        return $out
    } finally { Pop-Location }
}
$script:bdWarnings = @()

$repoDir = "D:\Public\github\$Root\$Repo"
$beads = Join-Path $repoDir '.beads'
$work = Join-Path $WorkRoot "${Root}__$Repo"
$build = Join-Path $work 'build'
$staging = Join-Path $work 'staging\.beads'
$replaced = Join-Path $work 'replaced'
if ($ResumeVerify) {
    if (-not (Test-Path (Join-Path $work 'migrate.json'))) { throw "nothing to resume: $work" }
    $prev = Get-Content (Join-Path $work 'migrate.json') -Raw | ConvertFrom-Json
    if ($prev.stage -ne 'verify') { throw "resume is only for runs that stopped at verify (stopped at: $($prev.stage))" }
    $log = [ordered]@{}
    foreach ($p in $prev.PSObject.Properties) { $log[$p.Name] = $p.Value }
    $log.resumedAt = (Get-Date).ToString('o'); $log.error = $null
    $expected = [int]$prev.expected
} else {
    if (Test-Path $work) { throw "work folder already exists: $work" }
    New-Item -ItemType Directory -Force $work | Out-Null
    $log = [ordered]@{ repo = $repoDir; prefix = $Prefix; stage = 'check'; ok = $false; startedAt = (Get-Date).ToString('o') }
}
try {
  if (-not $ResumeVerify) {
    # 1. バックアップの時点から変わっていないか
    $expectedHash = (Import-Csv $BackupSummary | Where-Object { $_.Repo -eq "$Root\$Repo" }).TreeHash
    if (-not $expectedHash) { throw "no backup record for $Root\$Repo" }
    $nowHash = Get-TreeHash $beads
    "backup hash : $expectedHash"
    "current hash: $nowHash"
    if ($nowHash -ne $expectedHash) { throw '.beads changed since the backup; take a new backup first' }

    # 2. 作業フォルダで新しいストアを作り、突き合わせる
    $log.stage = 'build'
    "--- build (trial-cutover.ps1) ---"
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'trial-cutover.ps1') -Source $repoDir -WorkDir $build -Prefix $Prefix *> (Join-Path $work 'build.log')
    $r = Get-Content (Join-Path $build 'result.json') -Raw | ConvertFrom-Json
    "build result: ok=$($r.ok) stage=$($r.stage) original=$($r.original) new=$($r.exportNew) tombstones=$($r.tombstonesDropped) sourceUnchanged=$($r.sourceUnchanged)"
    if (-not ($r.ok -and $r.sourceUnchanged)) { throw "build failed: $($r.error)" }
    $expected = [int]$r.exportNew
    $log.original = $r.original; $log.expected = $expected; $log.tombstonesDropped = $r.tombstonesDropped

    # 3. 自動の書き出しを設定する
    $log.stage = 'configure'
    $cut = Join-Path $build 'cutover'
    foreach ($kv in @(@('export.auto', 'true'), @('export.git-add', 'true'), @('export.interval', '1s'))) {
        Invoke-Bd $cut @('config', 'set', $kv[0], $kv[1]) | Out-Null
    }
    "config      : $((Invoke-Bd $cut @('config', 'list')) -match 'export\.' -join ' / ')"

    # 4. 入れ替え
    $log.stage = 'swap'
    New-Item -ItemType Directory -Force (Split-Path $staging), $replaced | Out-Null
    Copy-Item (Join-Path $cut '.beads') $staging -Recurse
    Get-ChildItem $staging -Force -File | Where-Object { $_.Name -like '*.gate.lock*' -or $_.Name -in 'export-state.json', 'issues.jsonl' } | Remove-Item -Force
    if ((Get-TreeHash $beads) -ne $expectedHash) { throw '.beads changed during the build; aborting before the swap' }
    Move-Item $beads (Join-Path $replaced '.beads')
    Move-Item $staging $beads
    "swapped     : old .beads -> $replaced\.beads"

    # 5. issues.jsonl を 1.3.2 で書き出し直す
    $log.stage = 'export'
    Invoke-Bd $repoDir @('export', '-o', (Join-Path $beads 'issues.jsonl')) | ForEach-Object { "export      : $_" }

    # 6. ルートの .gitignore（*.db は足さない。SQLite を使うアプリの DB まで無視してしまうため）
    $log.stage = 'gitignore'
    $gi = Join-Path $repoDir '.gitignore'
    $giText = if (Test-Path $gi) { Get-Content $gi -Raw } else { '' }
    if ($giText -notmatch '(?m)^\*\.gate\.lock\*\s*$') {
        $sep = if ($giText -and -not $giText.EndsWith("`n")) { "`n" } else { '' }
        $nl = if ($giText -match "`r`n") { "`r`n" } else { "`n" }
        $block = "$sep${nl}# bd (beads) 1.3.2 runtime files$nl*.gate.lock*$nl.beads-credential-key$nl" -replace "`n", $nl -replace "`r`r", "`r"
        [System.IO.File]::AppendAllText($gi, $block, [System.Text.UTF8Encoding]::new($false))
        "gitignore   : added *.gate.lock* and .beads-credential-key"
    } else { "gitignore   : already has *.gate.lock*" }

    # 7. bd の hooks を消す（リポジトリ自身の .git/hooks のみ。.backup などの控えは残す）
    $log.stage = 'hooks'
    $removed = @()
    foreach ($n in 'pre-commit', 'post-merge', 'pre-push', 'post-checkout', 'prepare-commit-msg') {
        $p = Join-Path $repoDir ".git\hooks\$n"
        if (-not (Test-Path $p)) { continue }
        if ((Get-Content $p -Raw) -match 'bd \(beads\)|bd-hooks-version|BEADS INTEGRATION') { Remove-Item $p -Force; $removed += $n }
    }
    "hooks       : removed $(if ($removed) { $removed -join ', ' } else { '(none)' })"
    $log.hooksRemoved = $removed
  }

    # 8. このリポジトリでの役割（ローカルの git 設定。commit されない）
    $log.stage = 'verify'
    & git -C $repoDir config beads.role maintainer
    "beads.role  : $((& git -C $repoDir config --get beads.role) -join '')"

    # 9. リポジトリの中で確かめる
    "where       : $((Invoke-Bd $repoDir @('where')) | Select-Object -First 1)"
    $count = (((Invoke-Bd $repoDir @('list', '--all', '--json', '--limit', '0')) -join "`n") | ConvertFrom-Json).Count
    $verify = Join-Path $work 'verify-export.jsonl'
    Invoke-Bd $repoDir @('export', '--all', '-o', $verify) | Out-Null
    $a = [System.IO.File]::ReadAllLines((Join-Path $build 'candidate-export.jsonl')) | Where-Object { $_ } | Sort-Object
    $b = [System.IO.File]::ReadAllLines($verify) | Where-Object { $_ } | Sort-Object
    $same = (($a -join "`n") -eq ($b -join "`n"))
    $jsonlCount = @([System.IO.File]::ReadAllLines((Join-Path $beads 'issues.jsonl')) | Where-Object { $_ }).Count
    "verify      : list=$count expected=$expected issues.jsonl=$jsonlCount export identical to build=$same"
    if ($count -ne $expected -or -not $same) { throw 'in-place verification failed' }
    $log.count = $count; $log.jsonlLines = $jsonlCount
    $log.bdWarnings = @($script:bdWarnings | Sort-Object -Unique)
    if ($log.bdWarnings) { "bd warnings : $($log.bdWarnings -join ' | ')" }
    $log.ok = $true; $log.stage = 'done'
} catch {
    $log.error = "$_"
    "ERROR at $($log.stage): $_"
} finally {
    $log.finishedAt = (Get-Date).ToString('o')
    $log | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $work 'migrate.json')
    "RESULT      : ok=$($log.ok) stage=$($log.stage)"
    "--- git status ---"
    & git -C $repoDir status --short 2>&1
}
