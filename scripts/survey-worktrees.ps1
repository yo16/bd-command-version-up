# 各リポジトリの git worktree を調べる（読み取りのみ）
#   Locked: git worktree lock されているか
#   Dirty: 未コミットの変更（追跡外のファイルも含む）の数
#   Unmerged: worktree のブランチにあって、統合ブランチ（develop / dev / main）にない commit の数
#   Safe: Locked でなく、Dirty が 0 で、Unmerged が 0（git worktree remove で消してよい）
# 使い方: pwsh -NoProfile -File scripts\survey-worktrees.ps1 [-OutCsv <パス>]
param(
    [string]$OutCsv,
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv')
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:GIT_PAGER = 'cat'
$rows = foreach ($t in (Import-Csv $Inventory)) {
    $dir = "D:\Public\github\$($t.Root)\$($t.Repo)"
    $int = foreach ($b in 'develop', 'dev', 'main') { & git.exe -C $dir rev-parse --verify --quiet "refs/heads/$b" 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $b; break } }
    $porcelain = & git.exe -C $dir worktree list --porcelain
    $cur = $null
    $entries = @()
    foreach ($line in $porcelain + '') {
        if ($line -like 'worktree *') { $cur = [ordered]@{ path = $line.Substring(9); branch = ''; head = ''; locked = $false; prunable = $false } }
        elseif ($line -like 'HEAD *') { $cur.head = $line.Substring(5) }
        elseif ($line -like 'branch *') { $cur.branch = $line.Substring(7) -replace '^refs/heads/', '' }
        elseif ($line -like 'locked*') { $cur.locked = $true }
        elseif ($line -like 'prunable*') { $cur.prunable = $true }
        elseif ($line -eq '' -and $cur) { $entries += [pscustomobject]$cur; $cur = $null }
    }
    foreach ($e in $entries | Select-Object -Skip 1) {
        $exists = Test-Path $e.path
        $dirty = if ($exists) { @(& git.exe -C $e.path status --porcelain 2>$null).Count } else { -1 }
        $unmerged = [int]((& git.exe -C $dir rev-list --count "$int..$($e.head)" 2>$null) -join '')
        [pscustomobject]@{
            Repo = "$($t.Root)\$($t.Repo)"; Path = $e.path; Branch = $e.branch; Int = $int
            Locked = $e.locked; Prunable = $e.prunable; Exists = $exists; Dirty = $dirty; Unmerged = $unmerged
            Safe = (-not $e.locked) -and $exists -and ($dirty -eq 0) -and ($unmerged -eq 0)
        }
    }
}
$rows | Format-Table Repo, Branch, Locked, Exists, Dirty, Unmerged, Safe -AutoSize | Out-String -Width 220
"worktrees: $(@($rows).Count)  safe to remove: $(@($rows | Where-Object Safe).Count)"
if ($OutCsv) { $rows | Export-Csv $OutCsv -NoTypeInformation -Encoding utf8 }
