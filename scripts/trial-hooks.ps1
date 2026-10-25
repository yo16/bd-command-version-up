# 古い（0.49.0 の）hooks を、リハーサルの cutover（作業用のコピー）に置き、1.3.2 での hooks の移行を試す
#   1. 元のリポジトリの .git/hooks から bd の hooks をコピーする（元は読むだけ）
#   2. bd migrate hooks --dry-run で計画を見る
#   3. bd hooks install を実行し、できた hooks の中身を表示する
# 使い方: pwsh -NoProfile -File scripts\trial-hooks.ps1 -SourceRepo <元のリポジトリ> -Cutover <work\...\cutover>
param(
    [Parameter(Mandatory)][string]$SourceRepo,
    [Parameter(Mandatory)][string]$Cutover,
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'; $env:BEADS_DOLT_AUTO_START = '0'

$srcHooks = Join-Path $SourceRepo '.git\hooks'
$dstHooks = Join-Path $Cutover '.git\hooks'
foreach ($h in Get-ChildItem $srcHooks -File | Where-Object { $_.Name -notlike '*.sample' }) {
    Copy-Item $h.FullName $dstHooks -Force
    "copied hook : $($h.Name)"
}
Push-Location $Cutover
try {
    "--- bd hooks list (before) ---"
    & $NewBd hooks list 2>&1
    "--- bd migrate hooks --dry-run ---"
    & $NewBd migrate hooks --dry-run 2>&1
    "--- bd hooks install ---"
    & $NewBd hooks install 2>&1
    "exit code   : $LASTEXITCODE"
    "--- bd hooks list (after) ---"
    & $NewBd hooks list 2>&1
} finally { Pop-Location }
"--- files in .git/hooks ---"
Get-ChildItem $dstHooks -File | Where-Object { $_.Name -notlike '*.sample' } | ForEach-Object { "$($_.Name) ($($_.Length) bytes)" }
foreach ($n in 'pre-commit', 'post-merge') {
    "===== $n ====="
    Get-Content (Join-Path $dstHooks $n) -Raw
}
