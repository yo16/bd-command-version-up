# 本番移行（4b）の前に、各リポジトリの注意点を読み取りだけで調べる
#   - すでに git add 済みの変更（あると移行の commit に混ざる）
#   - エージェント向け文書がテンプレートどおりに直せるか（fix-agent-docs.ps1 -DryRun）
#   - .beads がバックアップを取ったときから変わっていないか
# 使い方: pwsh -NoProfile -File scripts\precheck-4b.ps1 [-Skip yo16\sql_viz_202604_old,yo16\calc_20260317]
param(
    [string[]]$Skip = @('yo16\sql_viz_202604_old', 'yo16\calc_20260317'),
    [string]$Inventory = (Join-Path $PSScriptRoot '..\docs\inventory_2026-10-25.csv'),
    [string]$BackupSummary = (Join-Path $PSScriptRoot '..\docs\backup_2026-10-25.csv')
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
$backup = @{}; foreach ($b in Import-Csv $BackupSummary) { $backup[$b.Repo] = $b.TreeHash }
foreach ($t in (Import-Csv $Inventory)) {
    $name = "$($t.Root)\$($t.Repo)"
    if ($name -in $Skip) { continue }
    $dir = "D:\Public\github\$name"
    $staged = @(& git -C $dir --no-optional-locks diff --cached --name-only 2>$null)
    $unchanged = (Get-TreeHash (Join-Path $dir '.beads')) -eq $backup[$name]
    $docs = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'fix-agent-docs.ps1') -RepoDir $dir -DryRun
    $tracked = @(& git -C $dir ls-files -- AGENTS.md CLAUDE.md .beads/issues.jsonl .beads/config.yaml .gitignore 2>$null)
    "== $name  branch=$((& git -C $dir rev-parse --abbrev-ref HEAD) -join '')  beads unchanged since backup=$unchanged  pre-staged=$($staged.Count)$(if ($staged) { ' (' + ($staged -join ', ') + ')' })"
    "   tracked: $($tracked -join ', ')"
    $docs | ForEach-Object { "   $_" }
}
