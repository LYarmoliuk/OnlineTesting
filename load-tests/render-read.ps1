param([string]$Summary = 'load-tests/results/student1/read-summary.json',
      [string]$Output = 'docs/lab5-read.md')

$ErrorActionPreference = 'Stop'
$rows = @(Get-Content $Summary -Raw | ConvertFrom-Json)
$resultDir = Split-Path -Parent $Summary
function N($value) { ([double]$value).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) }
$lines = @(
    '# Lab 5 — Scenario A: Read-intensive та вплив кешу',
    '',
    'Джерело: k6, окремі ступені постійної конкуренції після warm-up. RPS — HTTP-запити/с. Error Rate — відсоток невдалих HTTP-запитів.',
    '',
    '| Cache | VUs | Факт, с | RPS | HIT, % | Avg, мс | p50, мс | p95, мс | p99, мс | Errors, % | Failed checks |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
)
foreach ($r in $rows) {
    $lines += "| $($r.mode) | $($r.vus) | $(N $r.elapsedSeconds) | $(N $r.rps) | $(N $r.hitPct) | $(N $r.avgMs) | $(N $r.p50Ms) | $(N $r.p95Ms) | $(N $r.p99Ms) | $(N $r.errorPct) | $($r.checkFailures) |"
}
foreach ($mode in @('warm','disabled')) {
    $part = @($rows | Where-Object mode -eq $mode | Sort-Object vus)
    if ($part.Count -eq 0) { continue }
    $x = ($part | ForEach-Object { $_.vus }) -join ', '
    $rps = ($part | ForEach-Object { N $_.rps }) -join ', '
    $p99 = ($part | ForEach-Object { N $_.p99Ms }) -join ', '
    $rpsMax = [math]::Ceiling((($part.rps | Measure-Object -Maximum).Maximum) * 1.1)
    $p99Max = [math]::Ceiling((($part.p99Ms | Measure-Object -Maximum).Maximum) * 1.1)
    $lines += @(
        '',
        "## $mode — RPS за кількістю VUs",
        '',
        '```mermaid',
        'xychart-beta',
        "  x-axis VUs [$x]",
        "  y-axis RPS 0 --> $rpsMax",
        "  line [$rps]",
        '```',
        '',
        "## $mode — p99 за кількістю VUs",
        '',
        '```mermaid',
        'xychart-beta',
        "  x-axis VUs [$x]",
        "  y-axis ms 0 --> $p99Max",
        "  line [$p99]",
        '```'
    )
}
$warmReads = Get-Content (Join-Path $resultDir 'warm-db-reads.txt') -Raw
$disabledReads = Get-Content (Join-Path $resultDir 'disabled-db-reads.txt') -Raw
$warmRequests = (@($rows | Where-Object mode -eq 'warm' | Measure-Object requests -Sum)[0].Sum)
$disabledRequests = (@($rows | Where-Object mode -eq 'disabled' | Measure-Object requests -Sum)[0].Sum)
$warmPerRequest = if ($warmRequests -gt 0) { [double]$warmReads / $warmRequests } else { 0 }
$disabledPerRequest = if ($disabledRequests -gt 0) { [double]$disabledReads / $disabledRequests } else { 0 }
$readReduction = if ($disabledPerRequest -gt 0) { 100 * (1 - ($warmPerRequest / $disabledPerRequest)) } else { 0 }
$lines += @(
    '',
    "PostgreSQL tup_returned: warm=$($warmReads.Trim()), disabled=$($disabledReads.Trim()).",
    "Повернуті БД рядки на HTTP-запит: warm=$(N $warmPerRequest), disabled=$(N $disabledPerRequest). Відносне зменшення: $(N $readReduction)%.",
    '',
    'Це лічильник повернутих рядків на рівні БД, а не час CPU. Режим disabled зупиняє Redis: затримка включає очікування таймауту підключення, тому різницю latency не можна приписувати лише роботі з БД. Порівнюйте однакові VUs; пояснюйте p99 окремо від середнього та враховуйте, що генератор і SUT поділяють фізичний хост.'
)
$extended = @($rows | Where-Object { $_.targetSeconds -gt 0 -and $_.elapsedSeconds -gt $_.targetSeconds * 1.2 })
if ($extended.Count -gt 0) {
    $labels = ($extended | ForEach-Object { "$($_.mode) $($_.vus) VUs: $(N $_.elapsedSeconds) с замість $($_.targetSeconds) с" }) -join '; '
    $lines += @('', "Подовжені ступені: $labels. k6 враховує час завершення завислих запитів у RPS. Повторіть ці ступені перед висновком про насичення.")
}
$parent = Split-Path -Parent $Output
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$lines | Set-Content $Output -Encoding utf8
Write-Host "Report: $Output"
