# 棚卸しの全リポジトリについて、.beads のコピーで trial-cutover.ps1 を順に実行し、結果を表にまとめる
# 元の .beads はコピーするだけで開かない
# 使い方: pwsh -NoProfile -File scripts\rehearsal-all.ps1 -OutDir <work\rehearsal-日付>
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv')
)
$ErrorActionPreference = 'Stop'
if (Test-Path $OutDir) { throw "OutDir already exists: $OutDir" }
New-Item -ItemType Directory $OutDir | Out-Null
$trial = Join-Path $PSScriptRoot 'trial-cutover.ps1'

$rows = @()
foreach ($t in (Import-Csv $Inventory)) {
    $name = "$($t.Root)__$($t.Repo)"
    $work = Join-Path $OutDir $name
    $log = Join-Path $OutDir "$name.log"
    $src = "D:\Public\github\$($t.Root)\$($t.Repo)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & pwsh -NoProfile -File $trial -Source $src -WorkDir $work -Prefix $t.Prefix *> $log
    $sw.Stop()
    $r = Get-Content (Join-Path $work 'result.json') -Raw | ConvertFrom-Json
    $row = [pscustomobject]@{
        Root = $t.Root; Repo = $t.Repo; Prefix = $t.Prefix
        Ok = $r.ok; Stage = $r.stage; Error = $r.error
        Original = $r.original; ExportOld = $r.exportOld; ExportNew = $r.exportNew
        DbToOld = if ($r.dbToOld) { "m$($r.dbToOld.missing)/x$($r.dbToOld.extra)/d$($r.dbToOld.diffs)" } else { '' }
        DbToNew = if ($r.dbToNew) { "m$($r.dbToNew.missing)/x$($r.dbToNew.extra)/d$($r.dbToNew.diffs)" } else { '' }
        FullFields = if ($r.full) { (($r.full.fields.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ') } else { '' }
        TombstonesDropped = $r.tombstonesDropped
        JsonlToDb = if ($r.jsonlToDb) { "m$($r.jsonlToDb.missing)/x$($r.jsonlToDb.extra) " + (($r.jsonlToDb.fields.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ') } else { '' }
        UtcConverted = $r.utcConverted; Totals = $r.totals
        SourceUnchanged = $r.sourceUnchanged; Seconds = [int]$sw.Elapsed.TotalSeconds
    }
    $rows += $row
    "{0,-45} ok={1,-5} stage={2,-14} issues={3}/{4}/{5} tomb={6} db->new={7} full={8} jsonl->db={9} src_unchanged={10} {11}s" -f $name, $row.Ok, $row.Stage,
        $row.Original, $row.ExportOld, $row.ExportNew, $row.TombstonesDropped, $row.DbToNew, $row.FullFields, $row.JsonlToDb, $row.SourceUnchanged, $row.Seconds
}
$rows | Export-Csv (Join-Path $OutDir 'summary.csv') -NoTypeInformation -Encoding utf8
"ok: $(@($rows | Where-Object Ok).Count) / $($rows.Count)"
"summary: $(Join-Path $OutDir 'summary.csv')"
