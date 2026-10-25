# 各リポジトリのエージェント向け文書（AGENTS.md、CLAUDE.md など）に、意味が変わる bd コマンドが書かれているかを数える（読み取りのみ）
# 使い方: pwsh -NoProfile -File scripts\scan-agent-docs.ps1 [-OutCsv <パス>]
param(
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv'),
    [string]$OutCsv
)
$files = 'AGENTS.md', 'CLAUDE.md', '.claude\CLAUDE.md', 'CLAUDE.local.md', '.github\copilot-instructions.md', '.cursorrules'
# 0.49.0 と 1.3.2 で意味が変わる、またはなくなったコマンド
$patterns = [ordered]@{
    'bd sync'          = 'bd sync\b'
    'bd daemon'        = 'bd daemon\b'
    'bd onboard'       = 'bd onboard\b'
    '--no-daemon'      = '--no-daemon\b'
    'bd import'        = 'bd import\b'
    'bd export'        = 'bd export\b'
    'bd prime'         = 'bd prime\b'
    'bd (any)'         = '\bbd [a-z]'
}
$rows = foreach ($t in (Import-Csv $Inventory)) {
    $repo = "D:\Public\github\$($t.Root)\$($t.Repo)"
    foreach ($f in $files) {
        $p = Join-Path $repo $f
        if (-not (Test-Path $p)) { continue }
        $text = Get-Content $p -Raw
        $row = [ordered]@{ Repo = $t.Repo; File = $f }
        foreach ($k in $patterns.Keys) { $row[$k] = ([regex]::Matches($text, $patterns[$k])).Count }
        $row['Tracked'] = if (& git -C $repo ls-files -- $f.Replace('\', '/') 2>$null) { 'yes' } else { 'no' }
        [pscustomobject]$row
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 250
if ($OutCsv) { $rows | Export-Csv $OutCsv -NoTypeInformation -Encoding utf8 }
