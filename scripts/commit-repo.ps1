# 移行したリポジトリで、移行で変わったファイルだけを commit する（push はしない）
#   - commit の前に、ほかの変更が git add されていないことを確かめる（あれば止める）
#   - git add するもの: .beads 以下の追跡中のファイル（変更・削除）、.gitignore（新規でも）、追跡中のエージェント向け文書
#   - bd と関係のない変更や、追跡していない文書は commit しない
# 使い方: pwsh -NoProfile -File scripts\commit-repo.ps1 -RepoDir <リポジトリ> [-ExtraLine "..."] [-DryRun]
param(
    [Parameter(Mandatory)][string]$RepoDir,
    [string[]]$ExtraLine = @(),
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$docs = 'AGENTS.md', 'CLAUDE.md', '.claude/CLAUDE.md', 'CLAUDE.local.md'

$pre = @(& git -C $RepoDir diff --cached --name-only)
if ($pre) { throw "already staged in ${RepoDir}: $($pre -join ', ')" }

& git -C $RepoDir add -u -- .beads
$gi = Join-Path $RepoDir '.gitignore'
if ((Test-Path $gi) -and (& git -C $RepoDir status --porcelain -- .gitignore)) { & git -C $RepoDir add -- .gitignore }
$trackedDocs = @($docs | Where-Object { & git -C $RepoDir ls-files -- $_ })
if ($trackedDocs) { & git -C $RepoDir add -u -- @trackedDocs }

$staged = @(& git -C $RepoDir diff --cached --name-status)
"staged:"
$staged | ForEach-Object { "  $_" }
if (-not $staged) { "nothing to commit"; return }

$names = @(& git -C $RepoDir diff --cached --name-only)
$lines = @()
if ($names -match '^\.beads/') {
    $lines += '- .beads now uses embedded Dolt (bd 1.3.2); issues.jsonl is re-exported'
    $lines += '  in the 1.3.2 format and kept current by export.auto / export.git-add'
}
if ($names -contains '.beads/interactions.jsonl' -and (& git -C $RepoDir diff --cached --name-status -- .beads/interactions.jsonl) -match '^D') {
    $lines += '- Remove the empty, unused interactions.jsonl'
}
if ($names -contains '.gitignore') { $lines += '- Ignore bd 1.3.2 runtime files (*.gate.lock*, .beads-credential-key)' }
$docNames = @($names | Where-Object { $_ -in $docs })
if ($docNames) {
    $lines += "- $($docNames -join ', '): update bd instructions for 1.3.2 (bd onboard ->"
    $lines += '  bd prime; drop bd sync, which now pushes to a Dolt remote; warn against'
    $lines += '  bd dolt push / remote add)'
}
$lines += $ExtraLine
$msg = "chore(beads): migrate issue store to bd 1.3.2`n`n$($lines -join "`n")`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
"message:"
$msg -split "`n" | ForEach-Object { "  $_" }
if ($DryRun) { & git -C $RepoDir reset --quiet; "dry run: unstaged again"; return }

$msgFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($msgFile, $msg, [System.Text.UTF8Encoding]::new($false))
    & git -C $RepoDir commit -F $msgFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git commit failed in $RepoDir (exit $LASTEXITCODE)" }
} finally { Remove-Item $msgFile -Force }
"commit: $((& git -C $RepoDir rev-parse --short HEAD) -join '') on $((& git -C $RepoDir rev-parse --abbrev-ref HEAD) -join '')"
