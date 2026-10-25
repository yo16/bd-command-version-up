# 新しい hooks を入れた作業用のコピーで、PATH 上の bd が 0.49.0 の場合と 1.3.2 の場合に commit がどうなるかを試す
# 作業用のコピーは独立した git リポジトリ（origin なし）。空の commit を作るだけ
# 使い方: pwsh -NoProfile -File scripts\trial-hook-commit.ps1 -Cutover <work\...\cutover>
param(
    [Parameter(Mandatory)][string]$Cutover,
    [string]$OldBdDir = 'C:\Users\yoichiro\go\bin',
    [string]$NewBdDir = 'C:\Users\yoichiro\beads-bin\v1.3.2'
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'; $env:BEADS_DOLT_AUTO_START = '0'
$basePath = $env:PATH
foreach ($case in @(@{ name = 'PATH bd = 0.49.0 (go\bin)'; dir = $OldBdDir }, @{ name = 'PATH bd = 1.3.2'; dir = $NewBdDir })) {
    "===== $($case.name) ====="
    $env:PATH = "$($case.dir);$basePath"
    "bd on PATH  : $((Get-Command bd).Source)  ($((& bd version) -join ''))"
    & git -C $Cutover commit --allow-empty -m "hook test: $($case.name)" 2>&1
    "commit exit : $LASTEXITCODE"
}
$env:PATH = $basePath
"--- git log ---"
& git -C $Cutover log --oneline -5
