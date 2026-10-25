# 全リポジトリで、PATH 上の bd（1.3.2）を使って移行の結果を確かめる（読み取りのみ）
#   - bd list --all の件数がリハーサルの移行後の件数（tombstone を除く）と一致するか
#   - bd ready が動くか
#   - bd の hooks が残っていないか（実際に使われる hooks のフォルダ）
#   - .beads に未コミットの変更がないか
# 使い方: pwsh -NoProfile -File scripts\verify-all.ps1 [-OutCsv <パス>]
param(
    [string]$Rehearsal = (Join-Path $PSScriptRoot '..\docs\rehearsal_2026-10-25.csv'),
    [string]$OutCsv
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$rows = foreach ($t in (Import-Csv $Rehearsal)) {
    $dir = "D:\Public\github\$($t.Root)\$($t.Repo)"
    Push-Location $dir
    try {
        $listAll = & bd list --all --json --limit 0 2>$null
        $listOk = $LASTEXITCODE -eq 0
        $count = if ($listOk) { ((($listAll) -join "`n") | ConvertFrom-Json).Count } else { -1 }
        $null = & bd ready --json 2>$null
        $readyOk = $LASTEXITCODE -eq 0
        $warn = @(& bd ready 2>&1 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" } |
            Where-Object { $_ -notmatch 'no Dolt remote|is an export, not cross-machine|repair:' })
    } finally { Pop-Location }
    $hooksPath = (& git -C $dir config --get core.hooksPath 2>$null) -join ''
    $hookDir = if (-not $hooksPath) { Join-Path $dir '.git\hooks' } elseif ([System.IO.Path]::IsPathRooted($hooksPath)) { $hooksPath } else { Join-Path $dir $hooksPath }
    $bdHooks = @(Get-ChildItem $hookDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.sample' -and $_.Name -notlike '*.backup' } |
        Where-Object { (Get-Content $_.FullName -Raw) -match 'bd \(beads\)|bd-hooks-version|BEADS INTEGRATION' } | ForEach-Object Name)
    $dirty = @(& git -C $dir --no-optional-locks status --porcelain -- .beads .gitignore 2>$null)
    [pscustomobject]@{
        Repo = "$($t.Root)\$($t.Repo)"; Expected = [int]$t.ExportNew; Count = $count; CountOk = ($count -eq [int]$t.ExportNew)
        ReadyOk = $readyOk; BdHooks = ($bdHooks -join ','); BeadsDirty = ($dirty -join ' | ')
        Warnings = ($warn -join ' | ')
    }
}
$rows | Format-Table Repo, Expected, Count, CountOk, ReadyOk, BdHooks, BeadsDirty, Warnings -AutoSize | Out-String -Width 250
"count ok: $(@($rows | Where-Object CountOk).Count) / $(@($rows).Count)   ready ok: $(@($rows | Where-Object ReadyOk).Count)   bd hooks left: $(@($rows | Where-Object BdHooks).Count)   dirty: $(@($rows | Where-Object BeadsDirty).Count)"
if ($OutCsv) { $rows | Export-Csv $OutCsv -NoTypeInformation -Encoding utf8 }
