# 公式スクリプトの canonicalize 方式を PowerShell で再現し、.beads のコピーで最後まで通す
#   1. sealed-source: .beads のコピーを v0.49.6 で init --force → export
#   2. cutover: その JSONL を 1.3.2 で init --from-jsonl → export --all
#   3. 元の DB（pristine のコピー）、v0.49.6 の export、1.3.2 の export を 1 件ずつ突き合わせる
# - 元の .beads はコピーするだけで開かない（前後でハッシュを比べる）
# - 公式スクリプトの env -i は Windows では使わない（USERPROFILE などが消えるため）。代わりに必要な環境変数だけを足す
# 使い方: pwsh -NoProfile -File scripts\trial-cutover.ps1 -Source <リポジトリ> -WorkDir <work\trial\名前> -Prefix <接頭辞>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$Prefix,
    [string]$CanonBd = 'C:\Users\yoichiro\beads-bin\v0.49.6\bd.exe',
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
function Invoke-At($dir, $exe, [string[]]$arguments) {
    Push-Location $dir
    try {
        & $exe @arguments 2>&1
        "exit code   : $LASTEXITCODE"
        if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed" }
    } finally { Pop-Location }
}
function New-IsolatedRepo($dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    & git -C $dir init --quiet
    & git -C $dir config core.hooksPath .git/hooks
    & git -C $dir config user.name legacy-migration
    & git -C $dir config user.email legacy-migration@invalid
}
# JSONL を読み、issue ごとに比較用の要約を作る
function Read-Export($path) {
    $map = @{}; $kinds = @{}
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $o = $line | ConvertFrom-Json
        $k = if ($o._type) { $o._type } else { 'issue' }
        $kinds[$k] = 1 + ($kinds[$k] ?? 0)
        if ($k -ne 'issue') { continue }
        $map[$o.id] = [pscustomobject]@{
            status = $o.status; title = $o.title
            labels = @($o.labels).Where({ $_ }).Count
            deps = @($o.dependencies).Where({ $_ }).Count
            comments = @($o.comments).Where({ $_ }).Count
        }
    }
    return @{ map = $map; kinds = $kinds }
}
function Compare-Sets($label, $expected, $actual) {
    $missing = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) })
    $extra = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $diff = @()
    foreach ($id in $expected.Keys) {
        if (-not $actual.ContainsKey($id)) { continue }
        $e = $expected[$id]; $a = $actual[$id]
        foreach ($f in 'status', 'title', 'labels', 'deps', 'comments') {
            if ("$($e.$f)" -ne "$($a.$f)") { $diff += "$id.$f ($($e.$f) -> $($a.$f))" }
        }
    }
    "[$label] expected=$($expected.Count) actual=$($actual.Count) missing=$($missing.Count) extra=$($extra.Count) field diffs=$($diff.Count)"
    if ($missing) { "  missing: $($missing -join ', ')" }
    if ($extra) { "  extra  : $($extra -join ', ')" }
    $diff | Select-Object -First 20 | ForEach-Object { "  diff   : $_" }
}

if (Test-Path $WorkDir) { throw "WorkDir already exists: $WorkDir" }
$sealed = Join-Path $WorkDir 'sealed-source'
$cutover = Join-Path $WorkDir 'cutover'
$pristine = Join-Path $WorkDir 'pristine\.beads'
$exportOld = Join-Path $WorkDir 'export.jsonl'
$exportNew = Join-Path $WorkDir 'candidate-export.jsonl'
New-Item -ItemType Directory -Force (Split-Path $pristine) | Out-Null

# 1. コピー
$srcBeads = Join-Path $Source '.beads'
$srcBefore = Get-TreeHash $srcBeads
New-IsolatedRepo $sealed
Copy-Item $srcBeads -Destination (Join-Path $sealed '.beads') -Recurse
Copy-Item $srcBeads -Destination $pristine -Recurse
"source hash : $srcBefore"
"sealed copy : $(Get-TreeHash (Join-Path $sealed '.beads'))"

# 2. 基準: 元の DB（pristine のコピー）から issue ごとの要約を作る
$db = Join-Path $pristine 'beads.db'
$q = @"
select i.id, i.status, i.title,
  (select count(*) from labels l where l.issue_id = i.id) as labels,
  (select count(*) from dependencies d where d.issue_id = i.id) as deps,
  (select count(*) from comments c where c.issue_id = i.id) as comments
from issues i order by i.id;
"@
$original = @{}
foreach ($r in (((& sqlite3 -json $db $q) -join "`n") | ConvertFrom-Json)) {
    $original[$r.id] = [pscustomobject]@{ status = $r.status; title = $r.title; labels = $r.labels; deps = $r.deps; comments = $r.comments }
}
"original    : bd_version=$((& sqlite3 $db "select value from metadata where key='bd_version';") -join '') issues=$($original.Count)"

# 3. v0.49.6 で開き直して export
$env:BD_DISABLE_METRICS = '1'
$env:BD_DISABLE_EVENT_FLUSH = '1'
$env:BD_NON_INTERACTIVE = '1'
$env:BEADS_NO_DAEMON = '1'
$env:BEADS_AUTO_START_DAEMON = 'false'
$env:BEADS_DOLT_AUTO_START = '0'
$env:GIT_TERMINAL_PROMPT = '0'
"--- v0.49.6 init --force ---"
Invoke-At $sealed $CanonBd @('--no-daemon', '--no-auto-import', 'init', '--force', '--quiet', '--prefix', $Prefix)
"--- v0.49.6 export ---"
Invoke-At $sealed $CanonBd @('--no-daemon', '--no-auto-import', 'export', '--format', 'jsonl', '-o', $exportOld)

# 4. 1.3.2 で取り込み
New-IsolatedRepo $cutover
New-Item -ItemType Directory -Force (Join-Path $cutover '.beads') | Out-Null
Copy-Item $exportOld (Join-Path $cutover '.beads\issues.jsonl')
"--- v1.3.2 init --from-jsonl ---"
Invoke-At $cutover $NewBd @('init', '--from-jsonl', '--quiet', '--non-interactive', '--skip-hooks', '--skip-agents', '--prefix', $Prefix)
"cutover .beads: $((Get-ChildItem (Join-Path $cutover '.beads') -Force | ForEach-Object Name) -join ', ')"
"cutover root  : $((Get-ChildItem $cutover -Force | ForEach-Object Name) -join ', ')"
"metadata.json : $((Get-Content (Join-Path $cutover '.beads\metadata.json') -Raw) -replace '\s+', ' ')"
"--- v1.3.2 export --all ---"
Invoke-At $cutover $NewBd @('export', '--all', '-o', $exportNew)

# 5. 突き合わせ
$old = Read-Export $exportOld
$new = Read-Export $exportNew
"v0.49.6 export kinds: $(($old.kinds.Keys | Sort-Object | ForEach-Object { "$_=$($old.kinds[$_])" }) -join ' ')"
"v1.3.2 export kinds : $(($new.kinds.Keys | Sort-Object | ForEach-Object { "$_=$($new.kinds[$_])" }) -join ' ')"
Compare-Sets 'original DB -> v0.49.6 export' $original $old.map
Compare-Sets 'v0.49.6 export -> v1.3.2 export' $old.map $new.map
Compare-Sets 'original DB -> v1.3.2 export' $original $new.map

$srcAfter = Get-TreeHash $srcBeads
"source after: $srcAfter  (unchanged: $($srcBefore -eq $srcAfter))"
