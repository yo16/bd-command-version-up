# 移行後のストア（作業用のコピー）で、export.auto と export.git-add が期待どおりに動くかを試す
#   1. bd config set export.auto true / export.git-add true
#   2. issue を 1 件だけ書き換える（コピーなので元には影響しない）
#   3. issues.jsonl が更新され、git の index に入ったか（git add されたか）を見る
# 使い方: pwsh -NoProfile -File scripts\trial-export-auto.ps1 -Cutover <work\...\cutover>
param(
    [Parameter(Mandatory)][string]$Cutover,
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'; $env:BEADS_DOLT_AUTO_START = '0'
$jsonl = Join-Path $Cutover '.beads\issues.jsonl'
Push-Location $Cutover
try {
    # cutover の git は bd init が作った初期 commit だけなので、今の JSONL を commit して基準にする
    & git add -A 2>&1 | Out-Null
    & git commit --quiet -m 'baseline before export.auto test' 2>&1 | Out-Null
    "jsonl before: $((Get-FileHash $jsonl).Hash.Substring(0, 12)) $((Get-Item $jsonl).LastWriteTime.ToString('HH:mm:ss'))"
    "--- config set ---"
    & $NewBd config set export.auto true 2>&1
    & $NewBd config set export.git-add true 2>&1
    "--- config get ---"
    & $NewBd config get export.auto 2>&1
    & $NewBd config get export.git-add 2>&1
    "config.yaml export lines: $((Select-String -Path (Join-Path $Cutover '.beads\config.yaml') -Pattern '^\s*(export|auto|git-add)' | ForEach-Object Line) -join ' | ')"
    $id = (((& $NewBd list --json --limit 1 2>$null) -join "`n") | ConvertFrom-Json)[0].id
    "--- bd update $id --notes ---"
    & $NewBd update $id --notes 'export.auto test (scratch copy)' 2>&1
    "exit code   : $LASTEXITCODE"
    "jsonl after : $((Get-FileHash $jsonl).Hash.Substring(0, 12)) $((Get-Item $jsonl).LastWriteTime.ToString('HH:mm:ss'))"
    "--- git status ---"
    & git status --short 2>&1
    "--- git diff --cached --stat ---"
    & git diff --cached --stat 2>&1
    "note in jsonl: $([bool](Select-String -Path $jsonl -Pattern 'export.auto test' -SimpleMatch))"
} finally { Pop-Location }
