# Lab 9 — Performance Profiling

Спочатку змерджіть частину Студента 1, щоб був наявний `backend/OnlineTesting.Api/Profiling/Lab9Diagnostics.cs`, а потім установіть файли Студента 2 з кореня репозиторію:

```powershell
pwsh -NoProfile -File "C:\шлях\до\розпакованого\Lab9-OnlineTesting\Студент 2\install-lab9.ps1"
```

Після встановлення запустіть PowerShell із кореня репозиторію:

```powershell
pwsh -NoProfile -File scripts/verify-lab9.ps1
pwsh -NoProfile -File scripts/run-lab9.ps1
```

Скрипт створює синтетичний опублікований тест, 30 запитань з 4 варіантами кожне і спробу з відповідями. Цей самий запис використовується в режимах `single` і `split`; порядок прогону однаковий. За замовчуванням це швидкий smoke-прогін. Для звітних вимірювань:

```powershell
pwsh -NoProfile -File scripts/run-lab9.ps1 -DurationSeconds 60 -Vus 25 -Runs 3
```

Скрипт виводить один SQL `EXPLAIN (ANALYZE, BUFFERS)` для single-query та плани трьох компонентів split-query, k6 summary JSON/CSV, Docker CPU/memory samples і fixture metadata у `profiling/results`. Jaeger доступний на `http://localhost:16686`. Шукайте span `lab9.attempt.read`, атрибут `lab9.query.mode` та Npgsql-запити. Використовуйте однакові умови та порівнюйте медіани повторів у звіті. Після перегляду артефактів видаліть синтетичний тест з ID з повідомлення скрипта, якщо він більше не потрібен.

Установка не копіює `.env` і не змінює його. Конфігурація Jaeger ізольована в `docker-compose.profiling.yml`.
