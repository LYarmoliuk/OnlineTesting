param([string]$Summary='load-tests/results/lab6/summary.json',
      [string]$Output='docs/lab6-read-scaling.md',
      [int]$StageSeconds=30)
$ErrorActionPreference='Stop'
$rows=@(Get-Content $Summary -Raw|ConvertFrom-Json)
function N($value){([double]$value).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)}
$lines=@('# Lab 6 — читання: primary проти replica','',"Кожен ступінь тривав $StageSeconds с. Redis bypass; той самий Nginx і генератор k6 (1 CPU / 512 MiB).",'', '| Режим | VUs | RPS | p95, мс | p99, мс | Errors, % | Failed checks |','|---|---:|---:|---:|---:|---:|---:|')
foreach($r in $rows){$lines+="| $($r.mode) | $($r.vus) | $($r.rps) | $($r.p95Ms) | $($r.p99Ms) | $($r.errorPct) | $($r.failedChecks) |"}
foreach($mode in @('primary','replica')){
    $part=@($rows|Where-Object mode -eq $mode|Sort-Object vus)
    $x=($part|ForEach-Object vus)-join ', '
    $y=($part|ForEach-Object { N $_.rps })-join ', '
    $z=($part|ForEach-Object { N $_.p99Ms })-join ', '
    $lines+=@('',"## $mode — RPS і p99",'','```mermaid','xychart-beta',"  x-axis VUs [$x]",'  y-axis RPS 0 --> 3000',"  line [$y]",'```','','```mermaid','xychart-beta',"  x-axis VUs [$x]",'  y-axis ms 0 --> 600',"  line [$z]",'```')
}
$p50=@($rows|Where-Object{$_.mode -eq 'primary' -and $_.vus -eq 50})[0]
$p200=@($rows|Where-Object{$_.mode -eq 'primary' -and $_.vus -eq 200})[0]
$r50=@($rows|Where-Object{$_.mode -eq 'replica' -and $_.vus -eq 50})[0]
$r200=@($rows|Where-Object{$_.mode -eq 'replica' -and $_.vus -eq 200})[0]
if($p50 -and $p200 -and $r50 -and $r200){
    $lines+=@('', '## Висновок', '', "Primary: від 50 до 200 VUs RPS $($p50.rps) → $($p200.rps), p99 $($p50.p99Ms) → $($p200.p99Ms) мс. Replica: RPS $($r50.rps) → $($r200.rps), p99 $($r50.p99Ms) → $($r200.p99Ms) мс. Обидва режими насичуються біля 50–100 VUs: збільшення VUs майже не підвищує RPS і збільшує хвостову затримку.", 'Цей прогін вимірює тільки читання малого каталогу на одному Docker-хості. При однаковій кількості запитів replica не гарантує приросту RPS: її користь зростає, коли паралельно є суттєві записи на primary або генератор працює на окремому хості. Дані не доводять лінійного масштабування.')
}
$lines|Set-Content $Output -Encoding utf8
