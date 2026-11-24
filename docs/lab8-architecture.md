# ЛР8 — Resilience Profile кешованого читання

## Розподіл роботи

**Студент 1:** Redis distributed lock у cache-aside сервісі, request coalescing, compare-and-delete token lock, TTL jitter, negative caching та контрольні API для stampede/avalanche й лічильники джерела.

**Студент 2:** k6 сценарії unprotected/protected/penetration, запуск 500 VUs, збір метрик і формування звіту, інсталяційний та перевірочний PowerShell сценарії.

## Resilience Profile

- **Cache miss:** `GET /api/tests` та контрольний resource read захищені розподіленим lock; один API instance завантажує дані з PostgreSQL, інші чекають оновлений кеш.
- **Cache outage:** звичайний cache-aside шлях продовжує читання з PostgreSQL без координації; затримка та DB навантаження можуть зрости.
- **Expiration:** TTL jitter розподіляє завершення кешу списків; lock lease 15 секунд обмежує час блокування.
- **Missing IDs:** короткий 15-секундний negative cache зменшує повторні SQL-запити; поява нового запису може бути затримана до спливу TTL.
- **Failure bounds:** очікування coalesced запиту — до 2 секунд; повільніше завантаження може призвести до повторного DB-запиту. Lease без fencing token не підходить для довгих критичних операцій.

## Механізми

- `GET /api/lab8/resource/{id}?protectedMode=false` — контрольний сценарій без coalescing; паралельні MISS кожен читає джерело.
- `GET /api/lab8/resource/{id}?protectedMode=true` — Redis `SET NX` mutex на 15 секунд. Переможець завантажує джерело й кешує; інші повторно читають кеш до 2 секунд. Lock звільняється Lua compare-and-delete за token власника.
- Обидва endpoint-и stampede читають реальний останній тест з PostgreSQL; затримка 300 ms додається для виразного конкурентного виміру. Лічильник фіксує кожну спробу такого SQL-завантаження. Звичайний `GET /api/tests` також проходить через lock/coalescing.
- Список тестів кешується на 30 секунд ± випадкові 10 секунд; список питань — на 60 секунд ± 15 секунд. Фактичний TTL демонстраційного ресурсу повертається у `X-Cache-TTL-Seconds`.
- `GET /api/lab8/entity/{id}` демонструє Negative Cache: відсутній ID запам'ятовується на 15 секунд.
- `GET /api/lab8/avalanche?jitter=false|true&ttlSeconds=5` працює з групою з 20 ключів: синхронні TTL створюють хвилю одночасного завершення, незалежний jitter розподіляє завершення в часі. `avalancheDatabaseLoads` у `/metrics` рахує контрольні PostgreSQL-запити.
- `GET /api/lab8/metrics` повертає лічильники контрольних звернень до джерела; `DELETE /api/lab8/reset` очищає лічильники та ключі ЛР8.

## Перевірка і обмеження

```powershell
pwsh -NoProfile -File scripts/verify-lab8.ps1
pwsh -NoProfile -File load-tests/run-lab8.ps1 -Smoke
pwsh -NoProfile -File load-tests/run-lab8.ps1 -StageSeconds 30
```

Stampede та avalanche endpoint-и виконують реальні SELECT-и до PostgreSQL; затримка у stampede endpoint підсилює видимість конкурентної хвилі. Лічильники endpoint-ів є контрольним виміром цих запитів, для production слід додати метрики СУБД.

Повний запуск має 5 окремих сценаріїв по 500 VUs: unprotected/protected cache stampede, негативне кешування та avalanche із синхронним TTL/jitter. Кожен сценарій починає з очищеного кешу; smoke коротший і не гарантує очікування завершення TTL.

Distributed lock має lease TTL 15 секунд. Завислий loader може втратити lease; fencing/renewal потрібні для довгих операцій. Redis outage вимикає coalescing. Negative cache затримує появу нового запису до 15 секунд, якщо ключ не інвалідовано. Jitter знижує avalanche, але сам по собі не усуває stampede одного ключа.
