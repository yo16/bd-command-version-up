# 移行したリポジトリで、bd に 1 回だけ書き込み、issues.jsonl が自動で書き出されて git add されるかを確かめる
# 書き込みは closed の issue 1 件の notes への追記（--append-notes。今ある notes は消さない）
# 使い方: pwsh -NoProfile -File scripts\check-auto-export.ps1 -RepoDir <リポジトリ> [-Id <issue id>]
param(
    [Parameter(Mandatory)][string]$RepoDir,
    [string]$Id,
    [string]$Note = 'bd 1.3.2 への移行の確認（2026-10-25）: この追記で issues.jsonl の自動書き出しを確かめた。',
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'
$jsonl = Join-Path $RepoDir '.beads\issues.jsonl'
Push-Location $RepoDir
try {
    if (-not $Id) {
        $Id = (((& $NewBd list --status closed --json --limit 1 2>$null) -join "`n") | ConvertFrom-Json)[0].id
    }
    $before = (Get-FileHash $jsonl).Hash
    "issue       : $Id"
    "--- bd update --append-notes ---"
    & $NewBd update $Id --append-notes $Note 2>&1 | ForEach-Object { "  $_" }
    "exit code   : $LASTEXITCODE"
    $after = (Get-FileHash $jsonl).Hash
    "jsonl changed: $($before -ne $after)"
    "note in jsonl: $([bool](Select-String -Path $jsonl -Pattern $Note -SimpleMatch))"
    "staged       : $((& git diff --cached --name-only -- .beads/issues.jsonl) -join '')"
} finally { Pop-Location }
