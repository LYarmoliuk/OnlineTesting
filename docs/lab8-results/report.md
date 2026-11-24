# Lab 8 — Resilience Engineering

Статус: код і сценарії підготовлені; результати потрібно сформувати на запущеному Docker середовищі.

Після встановлення обох частин і запуску Docker виконайте:

```powershell
pwsh -NoProfile -File scripts/verify-lab8.ps1
pwsh -NoProfile -File load-tests/run-lab8.ps1 -Smoke
pwsh -NoProfile -File load-tests/run-lab8.ps1 -StageSeconds 30
```

Повний прогін створить `summary.json`, `latency-chart.svg` та оновить цей звіт. Він порівнює cache stampede, negative caching та synchronized avalanche/TTL jitter по 500 VUs на сценарій. До запуску не підставляйте вигадані результати: числову матрицю сформує скрипт після реального k6 вимірювання.

Порівняйте кількість PostgreSQL-завантажень, RPS, p95, p99 і помилки між режимами. Smoke на 10 VUs потрібен тільки для перевірки запуску; він не є доказом продуктивності при 500 VUs.
