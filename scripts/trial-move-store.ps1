# 作業フォルダで作った 1.3.2 の .beads を別の場所へ動かしても使えるかを試す
#   1. リハーサルの cutover\.beads を、新しい git リポジトリ（moved）へコピーする
#   2. moved で bd list / bd doctor を実行し、件数が変わらないかを見る
# 使い方: pwsh -NoProfile -File scripts\trial-move-store.ps1 -Cutover <work\...\cutover> -Dest <work\...\moved>
param(
    [Parameter(Mandatory)][string]$Cutover,
    [Parameter(Mandatory)][string]$Dest,
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:BD_DISABLE_METRICS = '1'; $env:BD_NON_INTERACTIVE = '1'; $env:BEADS_DOLT_AUTO_START = '0'
if (Test-Path $Dest) { throw "Dest already exists: $Dest" }
New-Item -ItemType Directory $Dest | Out-Null
& git -C $Dest init --quiet
& git -C $Dest config core.hooksPath .git/hooks
Copy-Item (Join-Path $Cutover '.beads') (Join-Path $Dest '.beads') -Recurse
function Count-Issues($dir) {
    Push-Location $dir
    try { (((& $NewBd list --all --json --limit 0 2>$null) -join "`n") | ConvertFrom-Json).Count } finally { Pop-Location }
}
"cutover count: $(Count-Issues $Cutover)"
"moved count  : $(Count-Issues $Dest)"
Push-Location $Dest
try {
    "--- bd where ---"
    & $NewBd where 2>&1
    "--- bd doctor ---"
    & $NewBd doctor 2>&1
    "doctor exit : $LASTEXITCODE"
} finally { Pop-Location }
