# 移行前のバックアップを取る（元のファイルは読むだけ）
#   <OutDir>\<ルート>\<リポジトリ>\.beads            .beads を丸ごと
#   <OutDir>\<ルート>\<リポジトリ>\hooks\<場所>\       実際に使われている hooks のフォルダと .git\hooks（*.sample 以外）
#   <OutDir>\<ルート>\<リポジトリ>\git-state.json      ブランチ、HEAD、core.hooksPath、.beads の git status
#   <OutDir>\bin\                                      PATH 上の bd.exe
#   <OutDir>\manifest.csv                              コピーしたすべてのファイルの SHA-256（コピー元とコピー先）
# .beads はコピーの前後でコピー元のハッシュを比べ、途中で書き換わっていたら NG にする
# 使い方: pwsh -NoProfile -File scripts\backup.ps1 -OutDir <backup\日付>
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv'),
    [string]$BdExe = 'C:\Users\yoichiro\go\bin\bd.exe'
)
$ErrorActionPreference = 'Stop'
if (Test-Path $OutDir) { throw "OutDir already exists: $OutDir" }
New-Item -ItemType Directory $OutDir | Out-Null

$manifest = [System.Collections.Generic.List[object]]::new()
function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
# コピー元とコピー先の各ファイルのハッシュを manifest に記録し、一致しないものの数を返す
function Add-Manifest($repo, $kind, $srcDir, $dstDir) {
    $bad = 0
    foreach ($f in Get-ChildItem $srcDir -Recurse -File -Force) {
        $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
        $dst = Join-Path $dstDir $rel
        $hs = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        $hd = if (Test-Path -LiteralPath $dst) { (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash } else { '' }
        if ($hs -ne $hd) { $bad++ }
        $manifest.Add([pscustomobject]@{ Repo = $repo; Kind = $kind; Path = $rel; Size = $f.Length; Source = $f.FullName; SourceSha256 = $hs; BackupSha256 = $hd; Match = ($hs -eq $hd) })
    }
    return $bad
}

$summary = foreach ($t in (Import-Csv $Inventory)) {
    $repoDir = "D:\Public\github\$($t.Root)\$($t.Repo)"
    $name = "$($t.Root)\$($t.Repo)"
    $dest = Join-Path $OutDir $name
    New-Item -ItemType Directory -Force $dest | Out-Null

    # .beads
    $src = Join-Path $repoDir '.beads'
    $before = Get-TreeHash $src
    Copy-Item $src (Join-Path $dest '.beads') -Recurse
    $after = Get-TreeHash $src
    $copyHash = Get-TreeHash (Join-Path $dest '.beads')
    $badBeads = Add-Manifest $name 'beads' $src (Join-Path $dest '.beads')

    # hooks（実際に使われているフォルダと .git\hooks。同じなら 1 つ）
    $hooksPath = (& git -C $repoDir config --get core.hooksPath 2>$null) -join ''
    $dirs = [ordered]@{ 'git-hooks' = (Join-Path $repoDir '.git\hooks') }
    if ($hooksPath) {
        $eff = if ([System.IO.Path]::IsPathRooted($hooksPath)) { $hooksPath } else { Join-Path $repoDir $hooksPath }
        if ((Resolve-Path $eff -ErrorAction SilentlyContinue).Path -ne (Resolve-Path $dirs['git-hooks']).Path) { $dirs['core-hooksPath'] = $eff }
    }
    $badHooks = 0; $hookFiles = @()
    foreach ($label in $dirs.Keys) {
        $hd = $dirs[$label]
        if (-not (Test-Path $hd)) { continue }
        $files = @(Get-ChildItem $hd -File -Force | Where-Object { $_.Name -notlike '*.sample' })
        if (-not $files) { continue }
        $hdst = Join-Path $dest "hooks\$label"
        New-Item -ItemType Directory -Force $hdst | Out-Null
        foreach ($f in $files) { Copy-Item $f.FullName $hdst; $hookFiles += "$label/$($f.Name)" }
        # .sample 以外だけをコピーしたので、manifest もそれだけを数える
        foreach ($f in $files) {
            $hs = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
            $hb = (Get-FileHash (Join-Path $hdst $f.Name) -Algorithm SHA256).Hash
            if ($hs -ne $hb) { $badHooks++ }
            $manifest.Add([pscustomobject]@{ Repo = $name; Kind = "hooks:$label"; Path = $f.Name; Size = $f.Length; Source = $f.FullName; SourceSha256 = $hs; BackupSha256 = $hb; Match = ($hs -eq $hb) })
        }
    }

    # git の状態（戻すときの参考）
    [ordered]@{
        repo = $repoDir
        branch = (& git -C $repoDir --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null) -join ''
        head = (& git -C $repoDir --no-optional-locks rev-parse HEAD 2>$null) -join ''
        coreHooksPath = $hooksPath
        beadsStatus = @(& git -C $repoDir --no-optional-locks status --porcelain -- .beads 2>$null)
        backedUpAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $dest 'git-state.json')

    $ok = ($before -eq $after) -and ($before -eq $copyHash) -and ($badBeads -eq 0) -and ($badHooks -eq 0)
    [pscustomobject]@{
        Repo = $name; Ok = $ok; SourceStable = ($before -eq $after); CopyMatches = ($before -eq $copyHash)
        BeadsFiles = @(Get-ChildItem $src -Recurse -File -Force).Count; BeadsBad = $badBeads
        Hooks = ($hookFiles -join ', '); HooksBad = $badHooks; TreeHash = $before
    }
}

# bd.exe
$binDir = Join-Path $OutDir 'bin'
New-Item -ItemType Directory $binDir | Out-Null
$ver = (& $BdExe version) -join ''
Copy-Item $BdExe (Join-Path $binDir 'bd.exe')
Set-Content -Encoding utf8 (Join-Path $binDir 'VERSION.txt') "$ver`nsource: $BdExe"
$hs = (Get-FileHash $BdExe -Algorithm SHA256).Hash
$hb = (Get-FileHash (Join-Path $binDir 'bd.exe') -Algorithm SHA256).Hash
$manifest.Add([pscustomobject]@{ Repo = '(bin)'; Kind = 'bin'; Path = 'bd.exe'; Size = (Get-Item $BdExe).Length; Source = $BdExe; SourceSha256 = $hs; BackupSha256 = $hb; Match = ($hs -eq $hb) })

$manifest | Export-Csv (Join-Path $OutDir 'manifest.csv') -NoTypeInformation -Encoding utf8
$summary | Export-Csv (Join-Path $OutDir 'summary.csv') -NoTypeInformation -Encoding utf8
$summary | Format-Table Repo, Ok, SourceStable, CopyMatches, BeadsFiles, BeadsBad, HooksBad, Hooks -AutoSize | Out-String -Width 250
"bd.exe      : $ver  sha256=$hs  match=$($hs -eq $hb)"
"files       : $($manifest.Count)  mismatched: $(@($manifest | Where-Object { -not $_.Match }).Count)"
"repos ok    : $(@($summary | Where-Object Ok).Count) / $(@($summary).Count)"
"size        : $([math]::Round((Get-ChildItem $OutDir -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB, 1)) MB"
