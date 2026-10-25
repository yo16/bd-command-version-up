# migrate-all.ps1 で移行したリポジトリについて、commit-repo.ps1 を 1 件ずつ実行する（push はしない）
# 1 件でも失敗したら、そこで止める
# 使い方: pwsh -NoProfile -File scripts\commit-all.ps1 -WorkRoot <work\cutover-日付>
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [string[]]$Skip = @('yo16\sql_viz_202604_old', 'yo16\calc_20260317'),
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv')
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rows = @()
foreach ($t in (Import-Csv $Inventory)) {
    $name = "$($t.Root)\$($t.Repo)"
    if ($name -in $Skip) { continue }
    $dir = "D:\Public\github\$name"
    $log = Join-Path $WorkRoot "$($t.Root)__$($t.Repo).commit.log"
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'commit-repo.ps1') -RepoDir $dir *> $log
    $text = Get-Content $log -Raw
    $commit = if ($text -match 'commit: (\S+) on (\S+)') { "$($Matches[1]) ($($Matches[2]))" } elseif ($text -match 'nothing to commit') { '(nothing)' } else { '' }
    $files = @(([regex]::Matches($text, '(?m)^  ([MADR])\t(.+)$')) | ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value.Trim())" })
    $rows += [pscustomobject]@{ Repo = $name; Commit = $commit; Files = ($files -join ', ') }
    "{0,-42} {1,-28} {2}" -f $name, $commit, ($files -join ', ')
    if (-not $commit) { "STOPPED at $name (see $log)"; break }
}
$rows | Export-Csv (Join-Path $WorkRoot 'commit-all.csv') -NoTypeInformation -Encoding utf8
