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
}
foreach ($scenario in @('write','workflow')) {
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
$lines += @(
    '',
    'Поріг p95 ≤ 500 мс та errors ≤ 1% — критерій стабільності для цього експерименту. Закрита VU-модель може приховувати coordinated omission: при повільних відповідях генератор починає менше нових ітерацій.'
)
$critical100 = @($rows | Where-Object { $_.scenario -eq 'workflow' -and $_.nodes -eq 3 -and $_.vus -eq 100 }) | Select-Object -First 1
$critical200 = @($rows | Where-Object { $_.scenario -eq 'workflow' -and $_.nodes -eq 3 -and $_.vus -eq 200 }) | Select-Object -First 1
$single200 = @($rows | Where-Object { $_.scenario -eq 'workflow' -and $_.nodes -eq 1 -and $_.vus -eq 200 }) | Select-Object -First 1
if ($critical100 -and $critical200 -and $single200) {
    $lines += @(
        '',
        '## Аналіз',
        '',
        "У workflow на трьох API від 100 до 200 VUs RPS змінюється з $(N $critical100.rps) до $(N $critical200.rps), а p99 — з $(N $critical100.p99Ms) до $(N $critical200.p99Ms) мс. Це ознака насичення між цими ступенями: пропускна здатність майже вирівнюється, повільний хвіст різко зростає.",
        "При 200 VUs середня затримка $(N $critical200.avgMs) мс приховує p99 $(N $critical200.p99Ms) мс. Черги запитів, конкуренція за CPU і підключення до БД можуть збільшувати хвіст непропорційно середньому.",
        "Масштабування workflow при 200 VUs: $(N $single200.rps) RPS на одному API проти $(N $critical200.rps) на трьох. Це вказує на спільний обмежувач поза кількістю API-вузлів; конкретний компонент слід підтвердити одночасними CPU/DB/k6 вимірюваннями."
    )
}
$parent = Split-Path -Parent $Output
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$lines | Set-Content $Output -Encoding utf8
Write-Host "Report: $Output"
