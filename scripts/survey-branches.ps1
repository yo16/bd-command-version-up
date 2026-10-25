# 各リポジトリのブランチの構成と、git の運用の決まり（文書の記述）を調べる
# 書き込みは git fetch だけ（リモート追跡ブランチの更新）。作業ツリーとブランチには触れない
# 使い方: pwsh -NoProfile -File scripts\survey-branches.ps1 [-NoFetch] [-OutCsv <パス>]
param(
    [switch]$NoFetch,
    [string]$OutCsv,
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv')
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$rulePattern = '(?i)pull request|\bPR\b|--no-ff|--ff-only|直接\s*push|直接 push|push\s*しない|禁止|protected|main\s*へ|main に'
$rows = foreach ($t in (Import-Csv $Inventory)) {
    $dir = "D:\Public\github\$($t.Root)\$($t.Repo)"
    if (-not $NoFetch) { & git -C $dir fetch --prune --quiet origin 2>&1 | Out-Null }
    $cur = (& git -C $dir rev-parse --abbrev-ref HEAD) -join ''
    $origin = (& git -C $dir remote get-url origin 2>$null) -join ''
    $default = ((& git -C $dir symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -join '') -replace '^origin/', ''
    $local = @(& git -C $dir for-each-ref --format='%(refname:short)' refs/heads | Where-Object { $_ -notlike 'worktree-agent-*' })
    $info = foreach ($b in $local) {
        $up = (& git -C $dir rev-parse --abbrev-ref "$b@{u}" 2>$null) -join ''
        $ab = if ($up) { ((& git -C $dir rev-list --left-right --count "$b...$up") -join '') -replace '\s+', '/' } else { 'no-upstream' }
        # 移行の commit（今いるブランチの HEAD）を含むか
        & git -C $dir merge-base --is-ancestor $cur $b 2>$null
        $has = $LASTEXITCODE -eq 0
        "$b[$ab$(if ($has) { ',has-migration' })]"
    }
    $docs = foreach ($f in 'CLAUDE.md', 'AGENTS.md') {
        $p = Join-Path $dir $f
        if (Test-Path $p) {
            Select-String -Path $p -Pattern $rulePattern | Where-Object { $_.Line -match '(?i)main|dev|develop|preview|branch|ブランチ|merge|マージ|push' } |
                ForEach-Object { "${f}:$($_.LineNumber): $($_.Line.Trim())" }
        }
    }
    $skills = @(Get-ChildItem (Join-Path $dir '.claude') -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\worktrees\\' } | ForEach-Object { $_.FullName.Substring($dir.Length + 1) })
    $wt = @(& git -C $dir worktree list --porcelain | Where-Object { $_ -like 'worktree *' }).Count - 1
    [pscustomobject]@{
        Repo = "$($t.Root)\$($t.Repo)"; Current = $cur; Default = $default; Origin = $origin
        Branches = ($info -join ' '); Worktrees = $wt; Skills = ($skills -join ', '); Rules = ($docs -join "`n")
    }
}
foreach ($r in $rows) {
    "== $($r.Repo)  current=$($r.Current)  default=$($r.Default)  worktrees=$($r.Worktrees)"
    "   origin  : $($r.Origin)"
    "   branches: $($r.Branches)"
    if ($r.Skills) { "   skills  : $($r.Skills)" }
    if ($r.Rules) { $r.Rules -split "`n" | ForEach-Object { "   rule    : $_" } }
}
if ($OutCsv) { $rows | Export-Csv $OutCsv -NoTypeInformation -Encoding utf8 }
