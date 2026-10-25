# 棚卸しの一覧の順に、migrate-repo.ps1 と fix-agent-docs.ps1 を 1 件ずつ実行する（commit はしない）
# 1 件でも失敗したら、そこで止める（それ以降のリポジトリには触らない）
# 使い方: pwsh -NoProfile -File scripts\migrate-all.ps1 -WorkRoot <work\cutover-日付> [-Skip ...]
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [string[]]$Skip = @('yo16\sql_viz_202604_old', 'yo16\calc_20260317'),
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv')
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$results = @()
foreach ($t in (Import-Csv $Inventory)) {
    $name = "$($t.Root)\$($t.Repo)"
    if ($name -in $Skip) { continue }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $log = Join-Path $WorkRoot "$($t.Root)__$($t.Repo).migrate.log"
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'migrate-repo.ps1') -Root $t.Root -Repo $t.Repo -Prefix $t.Prefix -WorkRoot $WorkRoot *> $log
    $m = Get-Content (Join-Path $WorkRoot "$($t.Root)__$($t.Repo)\migrate.json") -Raw | ConvertFrom-Json
    $docs = ''
    if ($m.ok) {
        $docs = (& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'fix-agent-docs.ps1') -RepoDir "D:\Public\github\$name") -join ' / '
    }
    $sw.Stop()
    $row = [pscustomobject]@{ Repo = $name; Ok = $m.ok; Stage = $m.stage; Original = $m.original; Count = $m.count; Tombstones = $m.tombstonesDropped
        Hooks = ($m.hooksRemoved -join ','); Seconds = [int]$sw.Elapsed.TotalSeconds; Error = $m.error; Docs = $docs }
    $results += $row
    "{0,-42} ok={1,-5} stage={2,-8} {3}->{4} tomb={5} hooks={6} {7}s" -f $name, $row.Ok, $row.Stage, $row.Original, $row.Count, $row.Tombstones, $row.Hooks, $row.Seconds
    if ($docs) { "    docs: $docs" }
    if (-not $m.ok) { "STOPPED at $name : $($m.error)"; break }
}
$results | Export-Csv (Join-Path $WorkRoot 'migrate-all.csv') -NoTypeInformation -Encoding utf8
"done: $(@($results | Where-Object Ok).Count) / $($results.Count)"
