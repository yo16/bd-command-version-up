# 24 か所の .beads を bd を使わずに棚卸しする（読み取りのみ）
# - DB は .db / -wal / -shm を OutDir\db-copies にコピーし、コピーを開く（immutable=1 だと WAL を読まないため）
# - git は --no-optional-locks で index を更新しない
# 使い方: pwsh -NoProfile -File scripts\inventory.ps1 -OutDir <このリポジトリの外の作業用フォルダ>
#         結果は OutDir\inventory.csv に出る
param([Parameter(Mandatory)][string]$OutDir)
$copyRoot = Join-Path $OutDir 'db-copies'

$roots = @(
    'D:\Public\github\yo16',
    'D:\Public\github\smallpiece2024',
    'D:\Public\github\machinokikakushitsu',
    'D:\Public\github\kuronekotaiwan-matsuri',
    'D:\Public\github\takatsu-connect',
    'D:\Public\github\small-piece-2023'
)
$standard = @('.gitignore', '.local_version', 'bd.sock', 'config.yaml', 'daemon.lock', 'daemon.log', 'daemon.pid',
    'interactions.jsonl', 'issues.jsonl', 'last-touched', 'metadata.json', 'README.md')

function Sql($db, $query) {
    $out = & sqlite3 -separator '|' $db $query 2>&1
    return $out
}

$rows = @()
$details = @()
$dirs = Get-ChildItem -Path $roots -Directory -Depth 1 -Filter .beads -Force -ErrorAction SilentlyContinue
foreach ($d in $dirs) {
    $repoDir = $d.Parent.FullName
    $root = Split-Path $d.Parent.Parent.FullName -Leaf
    $repo = Split-Path $repoDir -Leaf
    $files = Get-ChildItem $d.FullName -Force
    $dbFiles = @($files | Where-Object { $_.Name -like '*.db' })
    $db = $null
    if ($dbFiles.Count -ge 1) {
        $copyDir = Join-Path $copyRoot "$root\$repo"
        New-Item -ItemType Directory -Force $copyDir | Out-Null
        foreach ($f in $files | Where-Object { $_.Name -like "$($dbFiles[0].Name)*" }) {
            Copy-Item $f.FullName -Destination $copyDir -Force
        }
        $db = Join-Path $copyDir $dbFiles[0].Name
    }

    # DB
    $prefix = ''; $bdVer = ''; $dbStatus = ''; $dbTotal = ''; $dirty = ''; $deleted = ''
    if ($db) {
        $prefix = (Sql $db "select value from config where key='issue_prefix';") -join ''
        $bdVer = (Sql $db "select value from metadata where key='bd_version';") -join ''
        $st = Sql $db "select status, count(*) from issues group by status order by status;"
        $dbStatus = ($st | ForEach-Object { $_ -replace '\|', '=' }) -join ' '
        $dbTotal = (Sql $db "select count(*) from issues;") -join ''
        $dirty = (Sql $db "select count(*) from dirty_issues;") -join ''
        $deleted = (Sql $db "select count(*) from issues where deleted_at is not null;") -join ''
    }
    $walFile = $files | Where-Object { $_.Name -like '*.db-wal' }
    $wal = if ($walFile) { $walFile[0].Length } else { '' }

    # JSONL
    $jsonl = Join-Path $d.FullName 'issues.jsonl'
    $jsTotal = ''; $jsStatus = ''
    if (Test-Path $jsonl) {
        $counts = @{}
        $n = 0
        foreach ($line in [System.IO.File]::ReadLines($jsonl)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $n++
            $s = ($line | ConvertFrom-Json).status
            $counts[$s] = 1 + ($counts[$s] ?? 0)
        }
        $jsTotal = $n
        $jsStatus = ($counts.Keys | Sort-Object | ForEach-Object { "$_=$($counts[$_])" }) -join ' '
    }

    $extra = ($files | Where-Object { $_.Name -notin $standard -and $_.Name -notlike '*.db' -and $_.Name -notlike '*.db-*' } |
        ForEach-Object { if ($_.PSIsContainer) { $_.Name + '/' } else { $_.Name } }) -join ', '
    $localVer = if (Test-Path (Join-Path $d.FullName '.local_version')) { (Get-Content (Join-Path $d.FullName '.local_version') -Raw).Trim() } else { '' }
    $meta = if (Test-Path (Join-Path $d.FullName 'metadata.json')) { ((Get-Content (Join-Path $d.FullName 'metadata.json') -Raw) | ConvertFrom-Json | ConvertTo-Json -Compress) } else { '' }

    # git
    $isGit = Test-Path (Join-Path $repoDir '.git')
    $tracked = ''; $beadsChanges = ''; $ahead = ''; $branch = ''; $hooks = ''; $hooksPath = ''
    if ($isGit) {
        $branch = (& git -C $repoDir --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null) -join ''
        $tracked = if (& git -C $repoDir ls-files -- .beads/issues.jsonl 2>$null) { 'yes' } else { 'no' }
        $beadsChanges = @(& git -C $repoDir --no-optional-locks status --porcelain -- .beads 2>$null).Count
        $a = & git -C $repoDir rev-list --count '@{u}..HEAD' 2>$null
        $ahead = if ($LASTEXITCODE -eq 0) { ($a -join '') } else { 'no upstream' }
        $hooksPath = (& git -C $repoDir config --get core.hooksPath 2>$null) -join ''
        $hookDir = if (-not $hooksPath) { Join-Path $repoDir '.git\hooks' }
                   elseif ([System.IO.Path]::IsPathRooted($hooksPath)) { $hooksPath }
                   else { Join-Path $repoDir $hooksPath }
        if (Test-Path $hookDir) {
            $hooks = (Get-ChildItem $hookDir -File | Where-Object { $_.Name -notlike '*.sample' } |
                ForEach-Object {
                    $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $tag = if ($c -match 'bd-hooks-version:\s*(\S+)') { "bd $($Matches[1])" } elseif ($c -match '\bbd\b|beads') { 'bd?' } else { 'other' }
                    "$($_.Name)($tag)"
                }) -join ', '
        }
    }

    $rows += [pscustomobject]@{
        Root = $root; Repo = $repo; Prefix = $prefix; DbFiles = $dbFiles.Count
        DbSize = if ($dbFiles.Count -ge 1) { $dbFiles[0].Length } else { '' }; Wal = $wal
        DbVer = $bdVer; LocalVer = $localVer
        DbTotal = $dbTotal; DbStatus = $dbStatus; Deleted = $deleted; Dirty = $dirty
        JsonlTotal = $jsTotal; JsonlStatus = $jsStatus
        Branch = $branch; JsonlTracked = $tracked; BeadsChanges = $beadsChanges; Ahead = $ahead
        HooksPath = $hooksPath; Hooks = $hooks; Extra = $extra; Metadata = $meta
    }
}

$csv = Join-Path $OutDir 'inventory.csv'
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding utf8
$rows | Format-List
"CSV: $csv"
