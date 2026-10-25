# survey-worktrees.ps1 の結果で Safe（locked でない、未コミットの変更なし、commit はすべて統合ブランチにある）の worktree を消す
# --force は使わない（変更が残っていれば git が拒否する）。ブランチは消さない
# フォルダがもうない worktree の記録は git worktree prune で片づける
# 使い方: pwsh -NoProfile -File scripts\remove-safe-worktrees.ps1 -SurveyCsv <survey-worktrees.ps1 の CSV>
param([Parameter(Mandatory)][string]$SurveyCsv)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rows = Import-Csv $SurveyCsv
foreach ($r in $rows | Where-Object { $_.Safe -eq 'True' }) {
    $dir = "D:\Public\github\$($r.Repo)"
    $out = & git.exe -C $dir worktree remove $r.Path 2>&1
    "{0,-30} remove {1}: exit={2} {3}" -f $r.Repo, $r.Branch, $LASTEXITCODE, ($out -join ' ')
}
foreach ($repo in ($rows | Where-Object { $_.Exists -eq 'False' } | Select-Object -ExpandProperty Repo -Unique)) {
    $dir = "D:\Public\github\$repo"
    $out = & git.exe -C $dir worktree prune --verbose 2>&1
    "{0,-30} prune: exit={1}" -f $repo, $LASTEXITCODE
    $out | ForEach-Object { "    $_" }
}
