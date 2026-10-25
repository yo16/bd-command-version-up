# 移行の commit を、各リポジトリの dev / main（または PR）へ反映させる
#   - マージは <WorkRoot>\<名前> に一時的な worktree を作って行う（利用者の作業ツリーは切り替えない）
#   - マージで衝突したら中止し、そのリポジトリはそこで止める（ほかのリポジトリは続ける）
#   - force push はしない。push が拒否されたら止める
#   - release / preview には触れない
# 手順の種類:
#   merge <src> <dst> <mode>   mode: noff（--no-ff）、ffonly（--ff-only）、auto（fast-forward できなければマージ commit）
#   push <branch>              git push -u origin <branch>
#   pushas <local> <remote>    git push -u origin <local>:refs/heads/<remote>
#   pr <head> <base>           gh pr create（同じ head / base の PR がすでにあれば作らない）
# 使い方: pwsh -NoProfile -File scripts\propagate.ps1 -WorkRoot <work\merge> [-Only <ルート\リポジトリ>]
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [string[]]$Only = @(),
    [string[]]$Skip = @()
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
New-Item -ItemType Directory -Force $WorkRoot | Out-Null

$plan = [ordered]@{
    'yo16\calc_20260306'                      = @('push dev', 'pr dev main')
    'yo16\calc_20260317'                      = @('push dev', 'merge dev main auto', 'push main')
    'yo16\chromeext_insta_reels'              = @('push dev', 'pr dev main')
    'yo16\kakeizu'                            = @('push dev', 'merge dev main auto', 'push main')
    'yo16\keihi_track'                        = @('push dev', 'merge dev main auto', 'push main')
    'yo16\my_tenbin_ai'                       = @('push dev', 'pr dev main')
    'yo16\n8n-insights-viewer'                = @('merge main dev auto', 'push dev', 'pr dev main')
    'yo16\newsletter-ai-chat'                 = @('push dev', 'merge dev main auto', 'push main')
    'yo16\qr_code_create'                     = @('push dev', 'merge dev main auto', 'push main')
    'yo16\salon-daily-fetcher'                = @('push dev', 'merge dev main auto', 'push main')
    'yo16\simple-translator'                  = @('merge feature/bd-simple-translator-c2n.5 dev noff', 'push dev', 'pr dev main')
    'yo16\sql_viz_202604'                     = @('merge feature/bd-sql_viz_202604_2-ldb dev noff', 'push dev', 'merge dev main auto', 'push main')
    'yo16\two-device-translator'              = @('push dev', 'pr dev main')
    'smallpiece2024\bigquery-mcp'             = @('push dev', 'merge dev main ffonly', 'push main')
    'smallpiece2024\goto-goto'                = @('push main')
    'smallpiece2024\kuchikomi_helper'         = @('push main')
    'smallpiece2024\shien-mitsukaru'          = @('push main')
    'machinokikakushitsu\website2026'         = @('push dev', 'pr dev main')
    'kuronekotaiwan-matsuri\y2026'            = @('push main')
    'takatsu-connect\takatsu-connect-advisor' = @('merge feature/bd-takatsu-connect-advisor-4l4.2 dev noff', 'push dev', 'pr dev main')
    'takatsu-connect\tc-wrapper'              = @('push main')
    'small-piece-2023\minecraft_piece'        = @('pushas develop chore/bd-1.3.2', 'pr chore/bd-1.3.2 develop')
}

$prBody = @'
## Summary
- Migrate the bd (beads) issue store from bd 0.49.0 (SQLite) to bd 1.3.2 (embedded Dolt).
- `.beads/issues.jsonl` is re-exported in the 1.3.2 format and kept current by `export.auto` / `export.git-add`.
- bd git hooks were removed; agent docs no longer tell agents to run `bd sync`, which in 1.3.2 pushes to a Dolt remote.
- Until this reaches the base branch, checking out the base branch makes bd 1.3.2 show no issues (old `.beads/metadata.json`).

This PR also carries any commits on the head branch that were not yet in the base branch.

Migration record: https://github.com/yo16/bd-command-version-up

🤖 Generated with [Claude Code](https://claude.com/claude-code)
'@

# 入力を待って止まらないようにする（ページャー、認証の入力、ssh の確認）
$env:GIT_PAGER = 'cat'; $env:GIT_TERMINAL_PROMPT = '0'; $env:GIT_SSH_COMMAND = 'ssh -o BatchMode=yes'
# 関数名を git にすると、PowerShell は大文字小文字を区別しないので中の git が関数自身を呼んでしまう。名前を変え、git.exe を明示する
function Invoke-Git($dir) { $out = & git.exe -C $dir @args 2>&1; return @{ code = $LASTEXITCODE; out = ($out | ForEach-Object { "$_" }) } }
function Count($dir, $range) { (& git -C $dir rev-list --count $range 2>$null) -join '' }
function Has($dir, $ref) { & git -C $dir rev-parse --verify --quiet $ref 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }

function Invoke-Merge($dir, $name, $src, $dst, $mode) {
    $wt = Join-Path $WorkRoot ("$name`__$dst" -replace '[\\/]', '_')
    if (Test-Path $wt) { throw "temp worktree path exists: $wt" }
    $r = Invoke-Git $dir worktree add $wt $dst
    if ($r.code -ne 0) { throw "worktree add $dst failed: $($r.out -join ' ')" }
    try {
        if (Has $dir "refs/remotes/origin/$dst") {
            $behind = [int](Count $dir "$dst..origin/$dst"); $ahead = [int](Count $dir "origin/$dst..$dst")
            if ($behind -gt 0 -and $ahead -gt 0) { throw "$dst has diverged from origin/$dst (ahead $ahead, behind $behind)" }
            if ($behind -gt 0) {
                $r = Invoke-Git $wt merge --ff-only "origin/$dst"
                if ($r.code -ne 0) { throw "fast-forward $dst to origin/$dst failed: $($r.out -join ' ')" }
                "    $dst fast-forwarded to origin/$dst ($behind commits)"
            }
        }
        $msg = "Merge $src into $dst (bd 1.3.2 migration)"
        $args2 = switch ($mode) {
            'noff'   { @('merge', '--no-ff', '-m', $msg, $src) }
            'ffonly' { @('merge', '--ff-only', $src) }
            default  { @('merge', '--no-edit', '-m', $msg, $src) }
        }
        $r = Invoke-Git $wt @args2
        if ($r.code -ne 0) {
            Invoke-Git $wt merge --abort | Out-Null
            throw "merge $src -> $dst failed (aborted): $(($r.out | Select-Object -Last 8) -join ' ')"
        }
        "    merged $src -> $dst ($mode): $((($r.out) | Select-Object -First 1) -join '')  now $((& git -C $dir rev-parse --short $dst) -join '')"
    } finally {
        $r = Invoke-Git $dir worktree remove $wt
        if ($r.code -ne 0) { "    WARNING: worktree remove failed: $($r.out -join ' ')" }
    }
}

$results = @()
foreach ($name in $plan.Keys) {
    if ($Only -and $name -notin $Only) { continue }
    if ($name -in $Skip) { continue }
    $dir = "D:\Public\github\$name"
    $done = @(); $status = 'ok'; $note = ''
    "== $name"
    try {
        foreach ($step in $plan[$name]) {
            $p = $step -split ' '
            switch ($p[0]) {
                'merge' { Invoke-Merge $dir $name $p[1] $p[2] $p[3] }
                'push' {
                    $r = Invoke-Git $dir push -u origin $p[1]
                    if ($r.code -ne 0) { throw "push $($p[1]) failed: $(($r.out | Select-Object -Last 5) -join ' ')" }
                    "    pushed $($p[1]): $(($r.out | Where-Object { $_ -match '->' }) -join ' ')"
                }
                'pushas' {
                    $r = Invoke-Git $dir push -u origin "$($p[1]):refs/heads/$($p[2])"
                    if ($r.code -ne 0) { throw "push $($p[1]) as $($p[2]) failed: $(($r.out | Select-Object -Last 5) -join ' ')" }
                    "    pushed $($p[1]) as $($p[2]): $(($r.out | Where-Object { $_ -match '->' }) -join ' ')"
                }
                'pr' {
                    $url = (& git -C $dir remote get-url origin) -join ''
                    $repo = ($url -replace '^.*[:/]([^/:]+/[^/]+?)(\.git)?$', '$1')
                    $existing = (& gh pr list --repo $repo --head $p[1] --base $p[2] --state open --json url --jq '.[0].url' 2>&1) -join ''
                    if ($LASTEXITCODE -eq 0 -and $existing) { "    PR already open: $existing"; $note += "PR $existing (existing) " }
                    else {
                        $bodyFile = Join-Path $WorkRoot 'pr-body.md'
                        [System.IO.File]::WriteAllText($bodyFile, $prBody, [System.Text.UTF8Encoding]::new($false))
                        $out = & gh pr create --repo $repo --base $p[2] --head $p[1] --title 'chore(beads): migrate issue store to bd 1.3.2' --body-file $bodyFile 2>&1
                        if ($LASTEXITCODE -ne 0) { throw "gh pr create failed: $($out -join ' ')" }
                        $prUrl = ($out | Where-Object { "$_" -match '^https://' } | Select-Object -Last 1)
                        "    PR created: $prUrl"; $note += "PR $prUrl "
                    }
                }
            }
            $done += $step
        }
    } catch {
        $status = 'STOPPED'; $note += "$_"
        "    STOPPED: $_"
    }
    $results += [pscustomobject]@{ Repo = $name; Status = $status; Done = ($done -join '; '); Note = $note.Trim() }
}
$results | Export-Csv (Join-Path $WorkRoot 'propagate.csv') -NoTypeInformation -Encoding utf8 -Append
"done: $(@($results | Where-Object Status -eq 'ok').Count) / $($results.Count)"
