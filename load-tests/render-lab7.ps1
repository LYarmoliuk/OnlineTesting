param([string]$Results='docs/lab7-results',[string]$Output='docs/lab7-results/report.md')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dir=Join-Path $root $Results
$rows=@(Get-Content (Join-Path $dir 'summary.json') -Raw|ConvertFrom-Json)
$reshard=Get-Content (Join-Path $dir 'resharding.json') -Raw|ConvertFrom-Json
$metadata=Get-Content (Join-Path $dir 'run-metadata.json') -Raw|ConvertFrom-Json
$distribution=@('single','legacy','bucket')|ForEach-Object { Get-Content (Join-Path $dir "distribution-$_.json") -Raw|ConvertFrom-Json }
function Number($value){([double]$value).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)}
function PeakStats([string]$strategy,[string]$shard,[int]$vus) {
    $path=Join-Path $dir "hot-$strategy-$vus-docker-stats.txt"
    if(-not (Test-Path $path)) { return 'n/a' }
    $name=if($shard -eq 'shard-a'){'onlinetesting-db-1'}else{'onlinetesting-db_shard_b-1'}
    $values=@(Get-Content $path|Where-Object {$_ -like "*|$name|*"}|ForEach-Object {
        $part=$_ -split '\|'; [pscustomobject]@{cpu=[double]::Parse(($part[2] -replace '%',''),[Globalization.CultureInfo]::InvariantCulture);memory=($part[3] -split ' / ')[0]}
    }|Sort-Object cpu -Descending)
    if($values.Count -eq 0) { return 'n/a' }
    "$(Number $values[0].cpu)% CPU; $($values[0].memory) RAM"
}
$lines=[Collections.Generic.List[string]]::new()
$lines.Add('# Lab 7 — результати масштабування даних')
$lines.Add('')
$lines.Add('Вимірювання виконано через той самий Nginx і k6 у Docker (генератор: 1 CPU, 512 MiB). `single` пише лише на Shard A; `legacy` маршрутизує за studentId; `bucket` — за studentId+attemptId через 64 віртуальні кошики та rendezvous ownership. Відсотки записів у таблиці нижче рахуються за фактичними приростами записів у двох фізичних БД.')
$lines.Add("Кожен режим читання використовує ті самі $($metadata.count) тестових подій на стратегію з типом $($metadata.seedType); старі події не потрапляють до результатів пошуку.")
$lines.Add('')
$lines.Add('## Базовий розподіл даних')
$lines.Add('')
$lines.Add('| Стратегія | Шард | Записи | Частка даних | Частка операцій запису |')
$lines.Add('|---|---|---:|---:|---:|')
foreach($d in $distribution){foreach($r in $d.rows){$lines.Add("| $($d.strategy) | $($r.shard) | $($r.records) | $($r.dataPct)% | $($r.writePct)% |")}}
$lines.Add('')
$lines.Add('## Порівняння читання')
$lines.Add('')
$lines.Add('| Топологія / запит | VUs | RPS | p95, мс | p99, мс | Помилки, % | Невдалі перевірки |')
$lines.Add('|---|---:|---:|---:|---:|---:|---:|')
foreach($r in $rows|Where-Object {$_.mode -notlike 'hot-*'}){$lines.Add("| $($r.mode) | $($r.vus) | $($r.rps) | $($r.p95Ms) | $($r.p99Ms) | $($r.errorPct) | $($r.failedChecks) |")}
$lines.Add('')
$lines.Add('Локальний запит шукає події однієї спроби на одному шарді; fan-out одночасно звертається до двох шардів, зливає результати і сортує їх. Це різні профілі запиту, тому RPS порівнює їхню фактичну вартість, а не лише швидкість вузлів.')
foreach($metric in @('rps','p99Ms')) {
    $vus=@($rows|Where-Object mode -eq 'single-local'|Sort-Object vus|ForEach-Object vus)-join ', '
    $max=[math]::Ceiling((@($rows|Where-Object {$_.mode -notlike 'hot-*'}|ForEach-Object {$_.$metric})|Measure-Object -Maximum).Maximum*1.15)
    $lines.Add('');$lines.Add("### $metric за кількістю VUs");$lines.Add('');$lines.Add('```mermaid');$lines.Add('xychart-beta')
    $lines.Add("  x-axis VUs [$vus]");$lines.Add("  y-axis $metric 0 --> $max")
    foreach($mode in @('single-local','sharded-local','fanout')) {
        $data=@($rows|Where-Object mode -eq $mode|Sort-Object vus|ForEach-Object { Number $_.$metric })-join ', '
        $lines.Add("  line [$data]")
    }
    $lines.Add('```')
    $lines.Add('Лінії в порядку: single-local, sharded-local, fanout.')
}
$lines.Add('');$lines.Add('## Сценарій гарячого шарду');$lines.Add('')
$lines.Add('| Стратегія | VUs | Шард A: записи | Шард B: записи | RPS | p95, мс | p99, мс | Найвищий зразок CPU/RAM A | Найвищий зразок CPU/RAM B |')
$lines.Add('|---|---:|---:|---:|---:|---:|---:|---|---|')
foreach($strategy in @('legacy','bucket')) {
    foreach($r in @($rows|Where-Object mode -eq "hot-$strategy"|Sort-Object vus)) {
        $d=@(Get-Content (Join-Path $dir "hot-$strategy-$($r.vus)-distribution.json") -Raw|ConvertFrom-Json)
        $a=@($d|Where-Object shard -eq 'shard-a')[0].writes;$b=@($d|Where-Object shard -eq 'shard-b')[0].writes
        $lines.Add("| $strategy | $($r.vus) | $a | $b | $($r.rps) | $($r.p95Ms) | $($r.p99Ms) | $(PeakStats $strategy 'shard-a' $r.vus) | $(PeakStats $strategy 'shard-b' $r.vus) |")
    }
}
$lines.Add('')
$legacy50=@($rows|Where-Object {$_.mode -eq 'hot-legacy' -and $_.vus -eq 50})[0]
$bucket50=@($rows|Where-Object {$_.mode -eq 'hot-bucket' -and $_.vus -eq 50})[0]
$lines.Add(('Порівняння 5 і 50 VUs показує стрибок хвостової затримки під навантаженням. При 50 VUs перехід до складеного ключа змінив p99 з {0} на {1} мс, а RPS — з {2} на {3}. Це вимірювання одного Docker-хоста, не гарантія такого самого приросту в іншому середовищі. CPU/RAM — зразки `docker stats` під час тесту; вони не є точними піками.' -f $legacy50.p99Ms,$bucket50.p99Ms,$legacy50.rps,$bucket50.rps))
$lines.Add('');$lines.Add('## Модель 2 → 3 шарди');$lines.Add('')
$lines.Add("Для $($reshard.keys) ключів простий `hash(key) % N` переміщує $($reshard.naiveMoved) записів ($($reshard.naiveMovedPct)%). За 64 віртуальними кошиками й rendezvous ownership змінюють власника $($reshard.movedBuckets) кошиків, або $($reshard.virtualMoved) записів ($($reshard.virtualMovedPct)%). Теоретична частка нового вузла — близько $($reshard.theoreticalNewShardSharePct)%. Це **модель плану міграції**, а не виконана жива міграція: перед додаванням Shard C потрібні копіювання даних кошиків, перевірка checksum, переключення карти й контроль відкату.")
$lines.Add('')
$lines.Add('## Межа насичення і обмеження');$lines.Add('')
foreach($mode in @('single-local','sharded-local','fanout')) {
    $part=@($rows|Where-Object mode -eq $mode|Sort-Object vus)
    $found=$false
    for($i=$part.Count-1;$i -ge 1;$i--) {
        if($part[$i].rps -le $part[$i-1].rps*1.05 -and $part[$i].p99Ms -gt $part[$i-1].p99Ms) {
            $lines.Add("- ${mode}: ознаки насичення між $($part[$i-1].vus) і $($part[$i].vus) VUs.")
            $found=$true;break
        }
    }
    if(-not $found){$lines.Add("- ${mode}: на виміряних рівнях чіткої межі насичення не виявлено.")}
}
$lines.Add('')
$lines.Add('Первинна БД ЛР6 одночасно є Shard A; його репліка не збільшує пропускну здатність записів. Глобальні JOIN і UNIQUE між шардами не забезпечуються локальними обмеженнями. Події журналу не беруть участі в транзакції основної спроби; для спільного запису потрібен outbox/Saga або 2PC.')
$path=Join-Path $root $Output
$lines|Set-Content $path -Encoding utf8
Write-Host "Report: $path"
