# .beads のコピーを v0.49.6 で開き直し（公式スクリプトの canonicalize と同じ init --force）、
# そのあと 1.3.2 の `bd migrate legacy-sqlite` で読めるかを試す
# - 元の .beads はコピーするだけで開かない
# - 比較用に、手を加える前のコピー（pristine）から issue ごとの id / status / title を取り出しておく
# 使い方: pwsh -NoProfile -File scripts\trial-canonicalize.ps1 -Source <リポジトリ> -WorkDir <work\trial\名前> -Prefix <接頭辞>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$Prefix,
    [string]$CanonBd = 'C:\Users\yoichiro\beads-bin\v0.49.6\bd.exe',
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
# sqlite3 と bd の出力（日本語のタイトル）を UTF-8 として受け取る
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
function Sql($db, $query) { & sqlite3 -separator '|' $db $query 2>&1 }
function Show-Db($label, $db) {
    "[$label] bd_version=$((Sql $db "select value from metadata where key='bd_version';") -join '')" +
    " total=$((Sql $db 'select count(*) from issues;') -join '')" +
    " status=$(((Sql $db 'select status, count(*) from issues group by status order by status;') -replace '\|', '=') -join ' ')"
}

if (Test-Path $WorkDir) { throw "WorkDir already exists: $WorkDir" }
$sealed = Join-Path $WorkDir 'sealed-source'
$pristine = Join-Path $WorkDir 'pristine\.beads'
$probe = Join-Path $WorkDir 'probe'
$out = Join-Path $WorkDir 'legacy-export.jsonl'
New-Item -ItemType Directory -Force $sealed, $probe, (Split-Path $pristine) | Out-Null

# 1. コピー
$srcBeads = Join-Path $Source '.beads'
$srcBefore = Get-TreeHash $srcBeads
Copy-Item $srcBeads -Destination (Join-Path $sealed '.beads') -Recurse
Copy-Item $srcBeads -Destination $pristine -Recurse
"source hash : $srcBefore"
"sealed copy : $(Get-TreeHash (Join-Path $sealed '.beads'))"

# 2. 比較用の基準（pristine のコピーを sqlite3 で開く。WAL も読まれる）
$expected = @{}
$json = (& sqlite3 -json (Join-Path $pristine 'beads.db') 'select id, status, title from issues order by id;') -join "`n"
foreach ($row in ($json | ConvertFrom-Json)) {
    $expected[$row.id] = $row
}
Show-Db 'original' (Join-Path $pristine 'beads.db')

# 3. 公式スクリプトと同じく、作業フォルダを独立した git リポジトリにする
& git -C $sealed init --quiet
& git -C $sealed config core.hooksPath .git/hooks
& git -C $sealed config user.name legacy-migration
& git -C $sealed config user.email legacy-migration@invalid

# 4. v0.49.6 で init --force
$env:BD_DISABLE_METRICS = '1'
$env:BD_NON_INTERACTIVE = '1'
$env:BEADS_NO_DAEMON = '1'
$env:BEADS_AUTO_START_DAEMON = 'false'
"--- v0.49.6 init --force ---"
Push-Location $sealed
try {
    & $CanonBd --no-daemon --no-auto-import init --force --prefix $Prefix 2>&1
    "exit code   : $LASTEXITCODE"
} finally { Pop-Location }
"sealed files: $((Get-ChildItem (Join-Path $sealed '.beads') -Force | ForEach-Object Name) -join ', ')"
"sealed root : $((Get-ChildItem $sealed -Force | ForEach-Object Name) -join ', ')"

# 5. 開き直したあとの DB（別のコピーで確かめる。sealed 自体は 1.3.2 で読むまで開かない）
$check = Join-Path $WorkDir 'after-0496-check'
New-Item -ItemType Directory -Force $check | Out-Null
Copy-Item (Join-Path $sealed '.beads\beads.db*') -Destination $check
Show-Db 'after v0.49.6' (Join-Path $check 'beads.db')

# 6. 1.3.2 で読む
# -C を付けると「beads project がない」と拒否されるので、公式スクリプトと同じく cd してから実行する
"--- v1.3.2 migrate legacy-sqlite ---"
Push-Location $probe
try {
    & $NewBd migrate legacy-sqlite --source-db (Join-Path $sealed '.beads\beads.db') --output $out 2>&1
    "exit code   : $LASTEXITCODE"
} finally { Pop-Location }
"probe files : $((Get-ChildItem $probe -Recurse -Force | ForEach-Object Name) -join ', ')"
"source after: $(Get-TreeHash $srcBeads)  (unchanged: $($srcBefore -eq (Get-TreeHash $srcBeads)))"

# 7. 1 件ずつ突き合わせる
if (Test-Path $out) {
    $kinds = @{}; $got = @{}
    foreach ($line in [System.IO.File]::ReadLines($out)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $o = $line | ConvertFrom-Json
        $k = if ($o._type) { $o._type } else { 'issue' }
        $kinds[$k] = 1 + ($kinds[$k] ?? 0)
        if ($k -eq 'issue') { $got[$o.id] = $o }
    }
    "export kinds: $(($kinds.Keys | Sort-Object | ForEach-Object { "$_=$($kinds[$_])" }) -join ' ')"
    $missing = @($expected.Keys | Where-Object { -not $got.ContainsKey($_) })
    $extra = @($got.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $diff = @($expected.Keys | Where-Object { $got.ContainsKey($_) -and
        ($got[$_].status -ne $expected[$_].status -or $got[$_].title -ne $expected[$_].title) })
    "compare     : expected=$($expected.Count) exported=$($got.Count) missing=$($missing.Count) extra=$($extra.Count) status/title diff=$($diff.Count)"
    if ($missing) { "missing ids : $($missing -join ', ')" }
    if ($extra) { "extra ids   : $($extra -join ', ')" }
    if ($diff) { "diff ids    : $($diff -join ', ')" }
    "fields      : $((((Get-Content $out -TotalCount 1) | ConvertFrom-Json).PSObject.Properties.Name) -join ', ')"
}
