# 公式スクリプトの canonicalize 方式を PowerShell で再現し、.beads のコピーで最後まで通す
#   1. sealed-source: .beads のコピーを v0.49.6 で init --force → export
#   2. cutover: その JSONL を 1.3.2 で init --from-jsonl → export --all
#   3. 突き合わせ
#      - 元の DB（pristine のコピー）と各 export: id ごとの status / title / ラベル数 / 依存数 / コメント数
#      - v0.49.6 の export と 1.3.2 の export: 公式スクリプトの normalize_export と同じ規則で全項目
# - 元の .beads はコピーするだけで開かない（前後でハッシュを比べる）
# - 公式スクリプトの env -i は Windows では使わない（USERPROFILE などが消えるため）。代わりに必要な環境変数だけを足す
# 使い方: pwsh -NoProfile -File scripts\trial-cutover.ps1 -Source <リポジトリ> -WorkDir <work\...\名前> -Prefix <接頭辞>
#         結果は <WorkDir>\result.json にも書き出す
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$Prefix,
    [string]$CanonBd = 'C:\Users\yoichiro\beads-bin\v0.49.6\bd.exe',
    [string]$NewBd = 'C:\Users\yoichiro\beads-bin\v1.3.2\bd.exe'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-TreeHash($dir) {
    $lines = Get-ChildItem $dir -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$($_.FullName.Substring($dir.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)) -replace '-', ''
}
function Invoke-At($dir, $exe, [string[]]$arguments) {
    Push-Location $dir
    try {
        & $exe @arguments 2>&1
        "exit code   : $LASTEXITCODE"
        if ($LASTEXITCODE -ne 0) { throw "$(Split-Path (Split-Path $exe) -Leaf) $($arguments -join ' ') failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
}
function New-IsolatedRepo($dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    & git -C $dir init --quiet
    & git -C $dir config core.hooksPath .git/hooks
    & git -C $dir config user.name legacy-migration
    & git -C $dir config user.email legacy-migration@invalid
}

# --- 公式スクリプトの normalize_export（132〜183 行）に合わせた正規化 ---
# 日時: 同じ時刻なら同じとみなす。秒より細かい部分は公式と同じく .5 以上を切り上げ、UTC の秒単位にそろえる
function ConvertTo-Stamp($v) {
    if ($v -isnot [string]) { return $v }
    $dto = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($v, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dto)) { return $v }
    $ticks = $dto.UtcTicks % [TimeSpan]::TicksPerSecond
    $dto = $dto.AddTicks(-$ticks)
    if ($ticks -ge [TimeSpan]::TicksPerSecond / 2) { $dto = $dto.AddSeconds(1) }
    return $dto.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
# 1.3.2 の取り込みは closed_at などの UTC 以外のオフセットを捨てる（上流 #5765。修正 e8839c4 は v1.3.2 に入っていない）。
# 入力が UTC（Z）なら正しく入るので、取り込む前に日時の項目だけを同じ時刻の UTC 表記に書き換える。
# 行のほかの部分は触らない（説明文の中の \"closed_at\" は、直前が \ なので対象にならない）
$TimestampKeys = 'created_at|updated_at|started_at|closed_at|due_at|defer_until|compacted_at|last_activity|deleted_at'
$TimestampPattern = [regex]('(?<!\\)"(' + $TimestampKeys + ')":"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?)([+-]\d{2}:\d{2})"')
function Convert-JsonlToUtc($inPath, $outPath) {
    $count = 0
    $lines = foreach ($line in [System.IO.File]::ReadLines($inPath)) {
        $TimestampPattern.Replace($line, {
            param($m)
            $script:utcConverted++
            $dto = [DateTimeOffset]::Parse($m.Groups[2].Value + $m.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
            '"' + $m.Groups[1].Value + '":"' + $dto.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFF', [Globalization.CultureInfo]::InvariantCulture).TrimEnd('.') + 'Z"'
        })
    }
    [System.IO.File]::WriteAllLines($outPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
}

function Get-Or($h, $key, $default) { if ($h.Contains($key) -and $null -ne $h[$key]) { $h[$key] } else { $default } }
function Sort-Deep($o) {
    if ($o -is [System.Collections.IDictionary]) {
        $r = [ordered]@{}
        foreach ($k in ($o.Keys | Sort-Object { $_ } -Culture 'en-US' -CaseSensitive)) { $r[$k] = Sort-Deep $o[$k] }
        return $r
    }
    if ($o -is [System.Collections.IList]) { return , @($o | ForEach-Object { Sort-Deep $_ }) }
    return $o
}
function ConvertTo-Normalized($h) {
    if ((Get-Or $h '_type' 'issue') -eq 'memory') {
        return [ordered]@{ kind = 'memory'; key = $h['key']; value = $h['value'] }
    }
    foreach ($k in '_type', 'comment_count', 'dependency_count', 'dependent_count') { $h.Remove($k) }
    foreach ($k in 'created_at', 'updated_at', 'started_at', 'closed_at', 'due_at', 'defer_until', 'compacted_at') {
        if ($h.Contains($k) -and $null -ne $h[$k]) { $h[$k] = ConvertTo-Stamp $h[$k] }
    }
    $h['labels'] = @(@(Get-Or $h 'labels' @()) | Sort-Object -Culture 'en-US' -CaseSensitive)
    $h['dependencies'] = @(@(Get-Or $h 'dependencies' @()) | ForEach-Object {
        [ordered]@{
            issue_id      = Get-Or $_ 'issue_id' ''
            depends_on_id = Get-Or $_ 'depends_on_id' (Get-Or $_ 'id' '')
            type          = Get-Or $_ 'type' (Get-Or $_ 'dependency_type' 'blocks')
            created_at    = ConvertTo-Stamp (Get-Or $_ 'created_at' '')
            created_by    = Get-Or $_ 'created_by' 'unknown'
            metadata      = Get-Or $_ 'metadata' '{}'
        } } | Sort-Object { $_.issue_id }, { $_.depends_on_id }, { $_.type })
    $h['comments'] = @(@(Get-Or $h 'comments' @()) | ForEach-Object {
        [ordered]@{
            issue_id   = Get-Or $_ 'issue_id' ''
            author     = Get-Or $_ 'author' ''
            text       = Get-Or $_ 'text' ''
            created_at = ConvertTo-Stamp (Get-Or $_ 'created_at' '')
        } } | Sort-Object { $_.issue_id }, { $_.author }, { $_.text })
    $h['kind'] = 'issue'
    return $h
}
# JSONL を読み、key（issue は id、memory は key）ごとの正規化済みレコードと、比較用の要約を返す
function Read-Export($path) {
    $full = @{}; $summary = @{}; $kinds = @{}
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $h = $line | ConvertFrom-Json -AsHashtable -DateKind String
        $kind = Get-Or $h '_type' 'issue'
        $kinds[$kind] = 1 + ($kinds[$kind] ?? 0)
        $n = ConvertTo-Normalized $h
        $key = if ($n.kind -eq 'memory') { "memory:$($n.key)" } else { $n['id'] }
        $full[$key] = Sort-Deep $n
        if ($n.kind -eq 'issue') {
            $summary[$key] = [pscustomobject]@{
                status = $n['status']; title = $n['title']
                labels = $n['labels'].Count; deps = $n['dependencies'].Count; comments = $n['comments'].Count
            }
        }
    }
    return @{ full = $full; summary = $summary; kinds = $kinds }
}
# $dropped: 1.3.2 が引き継がない tombstone（削除済み）の id。抜けていても想定内として別に数える
function Compare-Summary($label, $expected, $actual, $dropped = @{}) {
    $tomb = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) -and $dropped.ContainsKey($_) })
    $missing = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) -and -not $dropped.ContainsKey($_) })
    $extra = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $diff = @()
    foreach ($id in $expected.Keys) {
        if (-not $actual.ContainsKey($id)) { continue }
        foreach ($f in 'status', 'title', 'labels', 'deps', 'comments') {
            if ("$($expected[$id].$f)" -ne "$($actual[$id].$f)") { $diff += "$id.$f ($($expected[$id].$f) -> $($actual[$id].$f))" }
        }
    }
    "[$label] expected=$($expected.Count) actual=$($actual.Count) missing=$($missing.Count) tombstones dropped=$($tomb.Count) extra=$($extra.Count) field diffs=$($diff.Count)"
    if ($missing) { "  missing: $($missing -join ', ')" }
    if ($extra) { "  extra  : $($extra -join ', ')" }
    $diff | Select-Object -First 20 | ForEach-Object { "  diff   : $_" }
    return @{ missing = $missing.Count; tombstones = $tomb.Count; extra = $extra.Count; diffs = $diff.Count; detail = @($diff | Select-Object -First 50) }
}
function Compare-Full($label, $expected, $actual, $dropped = @{}) {
    $tomb = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) -and $dropped.ContainsKey($_) })
    $missing = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) -and -not $dropped.ContainsKey($_) })
    $extra = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $fieldCounts = @{}; $examples = @()
    foreach ($key in $expected.Keys) {
        if (-not $actual.ContainsKey($key)) { continue }
        $e = $expected[$key]; $a = $actual[$key]
        foreach ($f in @($e.Keys) + @($a.Keys) | Sort-Object -Unique) {
            $ej = ConvertTo-Json -InputObject ($e.Contains($f) ? $e[$f] : $null) -Depth 50 -Compress
            $aj = ConvertTo-Json -InputObject ($a.Contains($f) ? $a[$f] : $null) -Depth 50 -Compress
            if ($ej -ne $aj) {
                $fieldCounts[$f] = 1 + ($fieldCounts[$f] ?? 0)
                if ($examples.Count -lt 30) {
                    $short = { param($s) if ($s.Length -gt 160) { $s.Substring(0, 160) + '…' } else { $s } }
                    $examples += "$key.$f : $(& $short $ej) -> $(& $short $aj)"
                }
            }
        }
    }
    "[full: $label] expected=$($expected.Count) actual=$($actual.Count) missing=$($missing.Count) tombstones dropped=$($tomb.Count) extra=$($extra.Count) differing fields=$((($fieldCounts.Keys | Sort-Object | ForEach-Object { "$_=$($fieldCounts[$_])" }) -join ' '))"
    if ($missing) { "  missing: $($missing -join ', ')" }
    if ($extra) { "  extra  : $($extra -join ', ')" }
    $examples | ForEach-Object { "  diff   : $_" }
    return @{ missing = $missing.Count; tombstones = $tomb.Count; extra = $extra.Count; fields = $fieldCounts; examples = $examples }
}

if (Test-Path $WorkDir) { throw "WorkDir already exists: $WorkDir" }
$sealed = Join-Path $WorkDir 'sealed-source'
$cutover = Join-Path $WorkDir 'cutover'
$pristine = Join-Path $WorkDir 'pristine\.beads'
$exportOld = Join-Path $WorkDir 'export.jsonl'
$exportNew = Join-Path $WorkDir 'candidate-export.jsonl'
New-Item -ItemType Directory -Force (Split-Path $pristine) | Out-Null

$result = [ordered]@{ source = $Source; prefix = $Prefix; ok = $false; stage = 'copy'; error = $null }
$srcBeads = Join-Path $Source '.beads'
$srcBefore = Get-TreeHash $srcBeads
try {
    # 1. コピー
    New-IsolatedRepo $sealed
    Copy-Item $srcBeads -Destination (Join-Path $sealed '.beads') -Recurse
    Copy-Item $srcBeads -Destination $pristine -Recurse
    "source hash : $srcBefore"
    "sealed copy : $(Get-TreeHash (Join-Path $sealed '.beads'))"

    # 2. 基準: 元の DB（pristine のコピー）から issue ごとの要約を作る
    $result.stage = 'baseline'
    $db = Join-Path $pristine 'beads.db'
    $q = @"
select i.id, i.status, i.title,
  (select count(*) from labels l where l.issue_id = i.id) as labels,
  (select count(*) from dependencies d where d.issue_id = i.id) as deps,
  (select count(*) from comments c where c.issue_id = i.id) as comments
from issues i order by i.id;
"@
    $original = @{}
    foreach ($r in (((& sqlite3 -json $db $q) -join "`n") | ConvertFrom-Json)) {
        $original[$r.id] = [pscustomobject]@{ status = $r.status; title = $r.title; labels = $r.labels; deps = $r.deps; comments = $r.comments }
    }
    $totals = (& sqlite3 -separator '=' $db "select 'labels', count(*) from labels union all select 'deps', count(*) from dependencies union all select 'comments', count(*) from comments union all select 'events', count(*) from events;") -join ' '
    "original    : bd_version=$((& sqlite3 $db "select value from metadata where key='bd_version';") -join '') issues=$($original.Count) $totals"
    $result.original = $original.Count
    $result.totals = $totals

    # 3. v0.49.6 で開き直して export
    $env:BD_DISABLE_METRICS = '1'
    $env:BD_DISABLE_EVENT_FLUSH = '1'
    $env:BD_NON_INTERACTIVE = '1'
    $env:BEADS_NO_DAEMON = '1'
    $env:BEADS_AUTO_START_DAEMON = 'false'
    $env:BEADS_DOLT_AUTO_START = '0'
    $env:GIT_TERMINAL_PROMPT = '0'
    $result.stage = 'v0.49.6 init'
    "--- v0.49.6 init --force ---"
    Invoke-At $sealed $CanonBd @('--no-daemon', '--no-auto-import', 'init', '--force', '--quiet', '--prefix', $Prefix)
    # --allow-stale: 「JSONL の方が新しいかもしれない」という鮮度チェックを飛ばし、JSONL は取り込まずに DB の中身をそのまま出す。
    # DB の方が JSONL より新しいリポジトリがあるため（02_targets.md）。JSONL との違いは下の比較で参考として出す
    $result.stage = 'v0.49.6 export'
    "--- v0.49.6 export ---"
    Invoke-At $sealed $CanonBd @('--no-daemon', '--no-auto-import', '--allow-stale', 'export', '--format', 'jsonl', '-o', $exportOld)

    # 4. 日時を UTC 表記にそろえてから、1.3.2 で取り込み
    $result.stage = 'utc'
    $exportUtc = Join-Path $WorkDir 'export-utc.jsonl'
    $script:utcConverted = 0
    Convert-JsonlToUtc $exportOld $exportUtc
    "utc convert : $($script:utcConverted) timestamps rewritten to Z"
    $result.utcConverted = $script:utcConverted
    $result.stage = 'v1.3.2 init'
    New-IsolatedRepo $cutover
    New-Item -ItemType Directory -Force (Join-Path $cutover '.beads') | Out-Null
    Copy-Item $exportUtc (Join-Path $cutover '.beads\issues.jsonl')
    "--- v1.3.2 init --from-jsonl ---"
    Invoke-At $cutover $NewBd @('init', '--from-jsonl', '--quiet', '--non-interactive', '--skip-hooks', '--skip-agents', '--prefix', $Prefix)
    $meta = (Get-Content (Join-Path $cutover '.beads\metadata.json') -Raw) | ConvertFrom-Json
    "metadata.json : backend=$($meta.backend) dolt_mode=$($meta.dolt_mode) dolt_database=$($meta.dolt_database)"
    $result.backend = "$($meta.backend)/$($meta.dolt_mode)"
    $result.stage = 'v1.3.2 export'
    "--- v1.3.2 export --all ---"
    Invoke-At $cutover $NewBd @('export', '--all', '-o', $exportNew)

    # 5. 突き合わせ
    $result.stage = 'compare'
    $old = Read-Export $exportOld
    $new = Read-Export $exportNew
    "v0.49.6 export kinds: $(($old.kinds.Keys | Sort-Object | ForEach-Object { "$_=$($old.kinds[$_])" }) -join ' ')"
    "v1.3.2 export kinds : $(($new.kinds.Keys | Sort-Object | ForEach-Object { "$_=$($new.kinds[$_])" }) -join ' ')"
    $result.exportOld = $old.summary.Count
    $result.exportNew = $new.summary.Count
    $tombstones = @{}
    foreach ($id in $original.Keys) { if ($original[$id].status -eq 'tombstone') { $tombstones[$id] = $true } }
    $s1 = Compare-Summary 'original DB -> v0.49.6 export' $original $old.summary
    $s1 | Where-Object { $_ -is [string] }
    $s2 = Compare-Summary 'original DB -> v1.3.2 export' $original $new.summary $tombstones
    $s2 | Where-Object { $_ -is [string] }
    $f = Compare-Full 'v0.49.6 export -> v1.3.2 export' $old.full $new.full $tombstones
    $f | Where-Object { $_ -is [string] }
    # 参考: 元の issues.jsonl と DB の中身（v0.49.6 の export）の違い。JSONL の方が新しい変更を持っていないかを見る
    $origJsonl = Join-Path $pristine 'issues.jsonl'
    if (Test-Path $origJsonl) {
        $j = Compare-Full 'reference: original issues.jsonl -> DB (v0.49.6 export)' (Read-Export $origJsonl).full $old.full
        $j | Where-Object { $_ -is [string] }
        $j = $j | Where-Object { $_ -is [hashtable] }
        $result.jsonlToDb = $j
    }
    $s1 = $s1 | Where-Object { $_ -is [hashtable] }
    $s2 = $s2 | Where-Object { $_ -is [hashtable] }
    $f = $f | Where-Object { $_ -is [hashtable] }
    $result.dbToOld = $s1
    $result.dbToNew = $s2
    $result.full = $f
    $result.tombstonesDropped = $s2.tombstones
    $result.ok = ($s1.missing + $s1.extra + $s1.diffs + $s2.missing + $s2.extra + $s2.diffs + $f.missing + $f.extra + $f.fields.Count) -eq 0
    $result.stage = 'done'
} catch {
    $result.error = "$_"
    "ERROR at $($result.stage): $_"
} finally {
    $srcAfter = Get-TreeHash $srcBeads
    $result.sourceUnchanged = ($srcBefore -eq $srcAfter)
    "source after: $srcAfter  (unchanged: $($result.sourceUnchanged))"
    "RESULT      : ok=$($result.ok) stage=$($result.stage)"
    $result | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $WorkDir 'result.json')
}
