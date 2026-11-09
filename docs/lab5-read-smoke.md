# Lab 5 — Scenario A: Read-intensive та вплив кешу

Джерело: k6, окремі ступені постійної конкуренції після warm-up. RPS — HTTP-запити/с. Error Rate — відсоток невдалих HTTP-запитів.

| Cache | VUs | Факт, с | RPS | HIT, % | Avg, мс | p50, мс | p95, мс | p99, мс | Errors, % | Failed checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| warm | 1 | 2 | 453.28 | 100 | 2.07 | 1.92 | 3.08 | 3.57 | 0 | 0 |
| disabled | 1 | 3.12 | 0.64 | 0 | 1557.53 | 1557.53 | 1760.51 | 1778.55 | 0 | 0 |

## warm — RPS за кількістю VUs

```mermaid
xychart-beta
  x-axis VUs [1]
  y-axis RPS 0 --> 499
  line [453.28]
```

## warm — p99 за кількістю VUs

```mermaid
xychart-beta
  x-axis VUs [1]
  y-axis ms 0 --> 4
  line [3.57]
```

## disabled — RPS за кількістю VUs

```mermaid
xychart-beta
  x-axis VUs [1]
  y-axis RPS 0 --> 1
  line [0.64]
```

## disabled — p99 за кількістю VUs

```mermaid
xychart-beta
  x-axis VUs [1]
  y-axis ms 0 --> 1957
  line [1778.55]
```

PostgreSQL tup_returned: warm=138, disabled=140.
Повернуті БД рядки на HTTP-запит: warm=0.15, disabled=70. Відносне зменшення: 99.78%.

Це лічильник повернутих рядків на рівні БД, а не час CPU. Режим disabled зупиняє Redis: затримка включає очікування таймауту підключення, тому різницю latency не можна приписувати лише роботі з БД. Порівнюйте однакові VUs; пояснюйте p99 окремо від середнього та враховуйте, що генератор і SUT поділяють фізичний хост.

Подовжені ступені: disabled 1 VUs: 3.12 с замість 2 с. k6 враховує час завершення завислих запитів у RPS. Повторіть ці ступені перед висновком про насичення.
