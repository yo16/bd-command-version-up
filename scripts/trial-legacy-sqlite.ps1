# 1.3.2 の `bd migrate legacy-sqlite` が 0.49.0 の DB を読めるかを、.beads のコピーで試す
# - 元の .beads はコピーするだけで開かない
# - コピーのハッシュを実行の前後で比べ、書き換えられていないことを確かめる
# 使い方: pwsh -NoProfile -File scripts\trial-legacy-sqlite.ps1 -Source <リポジトリ> -WorkDir <work\trial\名前>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WorkDir,
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'

function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($dir.Length)
        "$rel $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}

if (Test-Path $WorkDir) { throw "WorkDir already exists: $WorkDir" }
$copy = Join-Path $WorkDir '.beads'
$probe = Join-Path $WorkDir 'probe'
$out = Join-Path $WorkDir 'legacy-export.jsonl'
New-Item -ItemType Directory -Force $WorkDir, $probe | Out-Null

$srcBeads = Join-Path $Source '.beads'
$srcBefore = Get-TreeHash $srcBeads
Copy-Item $srcBeads -Destination $copy -Recurse
$copyBefore = Get-TreeHash $copy
"source hash : $srcBefore"
"copy hash   : $copyBefore  (match: $($srcBefore -eq $copyBefore))"

$env:BD_DISABLE_METRICS = '1'
$env:BD_NON_INTERACTIVE = '1'
"--- bd migrate legacy-sqlite ---"
& $NewBd -C $probe migrate legacy-sqlite --source-db (Join-Path $copy 'beads.db') --output $out 2>&1
"exit code   : $LASTEXITCODE"

$copyAfter = Get-TreeHash $copy
$srcAfter = Get-TreeHash $srcBeads
"copy after  : $copyAfter  (unchanged: $($copyBefore -eq $copyAfter))"
"source after: $srcAfter  (unchanged: $($srcBefore -eq $srcAfter))"
"probe files : $((Get-ChildItem $probe -Recurse -Force | ForEach-Object Name) -join ', ')"

if (Test-Path $out) {
    $counts = @{}; $kinds = @{}; $n = 0
    foreach ($line in [System.IO.File]::ReadLines($out)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $n++
        $o = $line | ConvertFrom-Json
        $k = if ($o._type) { $o._type } else { 'issue' }
        $kinds[$k] = 1 + ($kinds[$k] ?? 0)
        if ($k -eq 'issue') { $counts[$o.status] = 1 + ($counts[$o.status] ?? 0) }
    }
    "export lines: $n"
    "kinds       : $(($kinds.Keys | Sort-Object | ForEach-Object { "$_=$($kinds[$_])" }) -join ' ')"
    "status      : $(($counts.Keys | Sort-Object | ForEach-Object { "$_=$($counts[$_])" }) -join ' ')"
    "fields      : $((((Get-Content $out -TotalCount 1) | ConvertFrom-Json).PSObject.Properties.Name) -join ', ')"
}
