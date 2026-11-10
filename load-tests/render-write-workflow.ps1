param([string]$Summary = 'load-tests/results/student2/write-workflow-summary.json',
      [string]$Output = 'docs/lab5-write-workflow.md')

$ErrorActionPreference = 'Stop'
$rows = @(Get-Content $Summary -Raw | ConvertFrom-Json)
function N($value) { ([double]$value).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) }
$lines = @(
    '# Lab 5 — Scenarios B/C та вплив масштабування',
    '',
    'Джерело: k6; ступені постійної конкуренції після warm-up. RPS — усі HTTP-запити/с, включно з кількома запитами в одному бізнес-циклі.',
    '',
    '| Scenario | API nodes | VUs | RPS | Avg, мс | p50, мс | p95, мс | p99, мс | Errors, % | Failed checks |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
)
foreach ($r in $rows) {
    $lines += "| $($r.scenario) | $($r.nodes) | $($r.vus) | $(N $r.rps) | $(N $r.avgMs) | $(N $r.p50Ms) | $(N $r.p95Ms) | $(N $r.p99Ms) | $(N $r.errorPct) | $($r.checkFailures) |"
}
$lines += @(
    '',
    '## Масштабування',
    '',
    '| Scenario | VUs | RPS 1 node | RPS 3 nodes | Speedup | Efficiency |',
    '|---|---:|---:|---:|---:|---:|'
)
foreach ($scenario in @('write','workflow')) {
    $one = @($rows | Where-Object { $_.scenario -eq $scenario -and $_.nodes -eq 1 })
    foreach ($a in $one) {
        $b = @($rows | Where-Object { $_.scenario -eq $scenario -and $_.nodes -eq 3 -and $_.vus -eq $a.vus }) | Select-Object -First 1
        if (-not $b -or $a.rps -le 0) { continue }
        $speedup = $b.rps / $a.rps
        $lines += "| $scenario | $($a.vus) | $(N $a.rps) | $(N $b.rps) | $(N $speedup) | $(N ($speedup / 3)) |"
    }
    $part = @($rows | Where-Object { $_.scenario -eq $scenario -and $_.nodes -eq 3 } | Sort-Object vus)
    if ($part.Count -eq 0) { continue }
    $x = ($part | ForEach-Object { $_.vus }) -join ', '
    $rps = ($part | ForEach-Object { N $_.rps }) -join ', '
    $p99 = ($part | ForEach-Object { N $_.p99Ms }) -join ', '
    $rpsMax = [math]::Ceiling((($part.rps | Measure-Object -Maximum).Maximum) * 1.1)
    $p99Max = [math]::Ceiling((($part.p99Ms | Measure-Object -Maximum).Maximum) * 1.1)
    $lines += @(
        '',
        "## $scenario — 3 вузли: RPS",
        '',
        '```mermaid',
        'xychart-beta',
        "  x-axis VUs [$x]",
        "  y-axis RPS 0 --> $rpsMax",
        "  line [$rps]",
        '```',
        '',
        "## $scenario — 3 вузли: p99",
        '',
        '```mermaid',
        'xychart-beta',
        "  x-axis VUs [$x]",
        "  y-axis ms 0 --> $p99Max",
        "  line [$p99]",
        '```'
    )
}
$stable = @($rows | Where-Object { $_.nodes -eq 3 -and $_.errorPct -le 1 -and $_.p95Ms -le 500 } | Sort-Object rps -Descending | Select-Object -First 1)
$unstable = @($rows | Where-Object { $_.nodes -eq 3 -and ($_.errorPct -gt 1 -or $_.p95Ms -gt 500) } | Sort-Object vus | Select-Object -First 1)
$lines += @(
    '',
    '## Попередня картка System Performance Baseline',
    '',
    '- Environment Config: 3 API, PostgreSQL, Redis; CPU/RAM та DB pool записати з environment.json студента 1 після обʼєднання.',
    "- Stable Throughput: $(if ($stable) { "$(N $stable[0].rps) RPS ($($stable[0].scenario), $($stable[0].vus) VUs)" } else { 'не визначено за порогом p95 ≤ 500 мс та errors ≤ 1%' }).",
    "- Saturation Point: $(if ($unstable) { "$($unstable[0].vus) VUs ($($unstable[0].scenario))" } else { 'не досягнуто у виміряних ступенях' }).",
    "- p95 / p99 Latency: $(if ($stable) { "$(N $stable[0].p95Ms) / $(N $stable[0].p99Ms) мс" } else { 'не визначено' }).",
    "- Error Rate at saturation: $(if ($unstable) { "$(N $unstable[0].errorPct)%" } else { 'не визначено' }).",
    '- Critical Scenario: визначити після порівняння зі сценарієм A студента 1.',
    '- Primary Bottleneck: висновок після зіставлення RPS, p99, ефективності масштабування та Docker/DB метрик.',
    '',
    'Пороги p95 ≤ 500 мс та errors ≤ 1% — робоче припущення для цієї лабораторної; їх можна змінити з поясненням. Закрита VU-модель може приховувати coordinated omission: при повільних відповідях генератор починає менше нових ітерацій. Для остаточного висновку повторіть граничні ступені довше й перевірте завантаження генератора, API, Redis та БД.'
)
$parent = Split-Path -Parent $Output
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$lines | Set-Content $Output -Encoding utf8
Write-Host "Report: $Output"
