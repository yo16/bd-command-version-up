# エージェント向け文書（AGENTS.md ほか）の、0.49.0 時代のテンプレートの記述を 1.3.2 向けに置き換える
#   R1: `bd onboard` → `bd prime`（このファイルと CLAUDE.md の決まりが優先すると添える）
#   R2: Quick Reference の `bd sync` の行を消し、JSONL は自動で書き出されること、bd sync / bd dolt push を実行しないことを書き足す
#   R3: Landing the Plane の `bd sync` の行を消す
# 改行コード（CRLF / LF）と文字コード（UTF-8、BOM の有無）は元のまま保つ。テンプレートと違う箇所は置き換えず、残った件数を出す
# 使い方: pwsh -NoProfile -File scripts\fix-agent-docs.ps1 -RepoDir <リポジトリ> [-DryRun]
param(
    [Parameter(Mandatory)][string]$RepoDir,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$files = 'AGENTS.md', 'CLAUDE.md', '.claude\CLAUDE.md', 'CLAUDE.local.md'

$guard = 'Do not run `bd sync`, `bd dolt push`, or `bd dolt remote add`: this project intentionally has no Dolt remote. ' +
    'Ignore the warning `beads: auto-export warning: no Dolt remote configured.` and the "repair" command it prints.'
$rules = @(
    @{ name = 'R1 onboard'
       pattern = 'Run `bd onboard` to get started\.'
       replace = 'Run `bd prime` to get started (the rules in this file and CLAUDE.md take precedence over its output).' },
    @{ name = 'R2 quick-ref sync'
       pattern = '(bd close <id>\s+# Complete work)(\r?\n)bd sync\s+# Sync with git(\r?\n)```'
       replace = '$1$2```$2$2`.beads/issues.jsonl` is written and `git add`-ed automatically after every bd write (`export.auto`), so there is no separate sync step.$2$2**' + $guard.Replace('$', '$$').Replace('Do not', 'Do not**') },
    @{ name = 'R3 landing sync'
       pattern = '(git pull --rebase)(\r?\n)(\s*)bd sync(\r?\n)'
       replace = '$1$2' }
)

foreach ($f in $files) {
    $p = Join-Path $RepoDir $f
    if (-not (Test-Path $p)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.UTF8Encoding]::new($false).GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    $new = $text
    $applied = @()
    foreach ($r in $rules) {
        $re = [regex]$r.pattern
        if ($re.IsMatch($new)) { $new = $re.Replace($new, $r.replace); $applied += $r.name }
    }
    # 書き足した注意書きの中の `bd sync` は数えない
    $rest = $new.Replace($guard.Replace('Do not', 'Do not**'), '')
    $left = [ordered]@{
        'bd sync'    = ([regex]::Matches($rest, 'bd sync\b')).Count
        'bd onboard' = ([regex]::Matches($rest, 'bd onboard\b')).Count
        'bd daemon'  = ([regex]::Matches($rest, 'bd daemon\b')).Count
        'flush-only' = ([regex]::Matches($rest, 'flush-only')).Count
    }
    $leftText = ($left.Keys | Where-Object { $left[$_] } | ForEach-Object { "$_=$($left[$_])" }) -join ' '
    "{0,-12} applied: {1,-45} remaining: {2}" -f $f, $(if ($applied) { $applied -join ', ' } else { '(none)' }), $(if ($leftText) { "$leftText  <- edit by hand" } else { 'none' })
    if ($new -ne $text -and -not $DryRun) {
        $enc = [System.Text.UTF8Encoding]::new($bom)
        [System.IO.File]::WriteAllText($p, $new, $enc)
    }
}
