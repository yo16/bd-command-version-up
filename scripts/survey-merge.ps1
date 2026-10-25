# 各リポジトリで、移行の commit を dev / main へ反映させるための状況を調べる（読み取りのみ。fetch 済みを前提にする）
#   Int: 統合ブランチ（dev、develop。なければ main）
#   CurHasMig: 今いるブランチ（移行の commit がある）
#   Int..: origin の統合ブランチに対する、ローカルの統合ブランチの ahead/behind
#   Cur->Int: 今いるブランチが統合ブランチと違う場合、今いるブランチにだけある commit の数（マージで入るもの）
#   Main: origin/main に対する、統合ブランチ（マージ後の想定）の ahead/behind。behind が 0 なら main は fast-forward できる
#   NonBd: origin/main と今いるブランチの差分のうち、bd 関係（.beads/、.gitignore、AGENTS.md、CLAUDE.md）以外のファイル数
# 使い方: pwsh -NoProfile -File scripts\survey-merge.ps1
param([string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv'))
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function Count($dir, $range) { $c = (& git -C $dir rev-list --count $range 2>$null) -join ''; if ($LASTEXITCODE -ne 0) { 'n/a' } else { $c } }
function Has($dir, $ref) { & git -C $dir rev-parse --verify --quiet $ref 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }
foreach ($t in (Import-Csv $Inventory)) {
    $dir = "D:\Public\github\$($t.Root)\$($t.Repo)"
    $cur = (& git -C $dir rev-parse --abbrev-ref HEAD) -join ''
    $int = if (Has $dir 'refs/heads/develop') { 'develop' } elseif (Has $dir 'refs/heads/dev') { 'dev' } else { 'main' }
    $originInt = Has $dir "refs/remotes/origin/$int"
    $originMain = Has $dir 'refs/remotes/origin/main'
    $intAB = if ($originInt) { "$(Count $dir "origin/$int..$int")/$(Count $dir "$int..origin/$int")" } else { 'no origin/' + $int }
    $curToInt = if ($cur -ne $int) { Count $dir "$int..$cur" } else { '-' }
    $mainAB = if ($originMain) { "$(Count $dir "origin/main..$cur")/$(Count $dir "$cur..origin/main")" } else { 'no origin/main' }
    $nonBd = if ($originMain) {
        @(& git -C $dir diff --name-only "origin/main...$cur" 2>$null | Where-Object { $_ -notmatch '^(\.beads/|\.gitignore$|AGENTS\.md$|CLAUDE\.md$)' }).Count
    } else { 'n/a' }
    $dirty = @(& git -C $dir --no-optional-locks status --porcelain --untracked-files=no 2>$null).Count
    $wt = @(& git -C $dir worktree list --porcelain | Where-Object { $_ -like 'worktree *' }).Count - 1
    "{0,-42} cur={1,-40} int={2,-8} int(local/origin)={3,-12} cur->int={4,-4} vs origin/main(ahead/behind)={5,-10} nonBd={6,-4} dirty={7} worktrees={8}" -f "$($t.Root)\$($t.Repo)", $cur, $int, $intAB, $curToInt, $mainAB, $nonBd, $dirty, $wt
}
