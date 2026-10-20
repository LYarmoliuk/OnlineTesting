
# OnlineTesting

## 1. Опис проєкту

OnlineTesting — вебсистема для створення та проходження онлайн-тестів.

Система дозволяє організатору створювати тести, додавати запитання та варіанти відповідей, публікувати тести.

Студенти можуть проходити опубліковані тести, зберігати відповіді та отримувати результати оцінювання.

## 2. Технології

- Backend: ASP.NET Core 10, C#
- Frontend: Vue 3, TypeScript, Vite
- Database: PostgreSQL 17
- ORM: Entity Framework Core
- Контейнеризація: Docker, Docker Compose
- Вебсервер frontend: Nginx
- API: REST, JSON, HTTP

## 3. Архітектура системи

Поточна конфігурація має два однакові API-вузли та спільну PostgreSQL:

1. Frontend — інтерфейс організатора та студента.
2. Backend — два взаємозамінні REST API-вузли `api_a` і `api_b`.
3. PostgreSQL — зберігання даних.

Схема взаємодії:

```text
Організатор / Студент
          |
          | HTTP :8081
          v
     Vue 3 + Nginx
          |
          | HTTP /api/*
          v
   Nginx балансування
       /          \
  API api-a     API api-b
       \          /
        PostgreSQL 17
          |
          v
 Docker Volume: postgres_data
```

Усі контейнери підключені до мережі testing-network. Nginx розподіляє запити `/api/` між `api_a` та `api_b` без прив'язки клієнта до вузла. Схеми C4 Container і C4 Component наведені в [архітектурній документації](docs/architecture.md).

Зовнішні інтеграції та черги повідомлень у поточній версії відсутні.

## 4. Доменна модель

Основні сутності:

- Test — тест, його назва, опис та статус публікації.
- Question — запитання, яке належить тесту.
- AnswerOption — варіант відповіді на запитання.
- TestAttempt — спроба проходження тесту.
- StudentAnswer — відповідь студента в межах спроби.

Зв'язки:

- Test 1:N Question
- Question 1:N AnswerOption
- Test 1:N TestAttempt
- TestAttempt 1:N StudentAnswer
- Question 1:N StudentAnswer

Дані зберігаються в PostgreSQL.

## 5. REST API

| Метод | Endpoint | Призначення |
|---|---|---|
| GET | /api/tests | Отримати список тестів |
| POST | /api/tests | Створити тест |
| PUT | /api/tests/{id} | Оновити тест або статус публікації |
| DELETE | /api/tests/{id} | Видалити тест |
| GET | /api/tests/{testId}/questions | Отримати запитання тесту |
| POST | /api/tests/{testId}/questions | Додати запитання |
| PUT | /api/questions/{id} | Оновити запитання |
| DELETE | /api/questions/{id} | Видалити запитання |
| GET | /api/questions/{questionId}/options | Отримати варіанти відповідей |
| POST | /api/questions/{questionId}/options | Додати варіант |
| POST | /api/tests/{testId}/attempts | Почати проходження тесту |
| PUT | /api/attempts/{attemptId}/answers | Зберегти відповідь |
| POST | /api/attempts/{attemptId}/submit | Завершити тест і обчислити результат |
| GET | /api/attempts/{attemptId}/result | Отримати результат |

API використовує HTTP-статуси 200, 201, 204, 400, 404, 409 залежно від операції та результату її виконання.

Для роботи із захищеними endpoint спроб використовується заголовок X-Attempt-Token.

## 6. Запуск системи

Необхідне програмне забезпечення:

- Docker Desktop
- Docker Compose

Перед запуском створити файл `.env` у корені проєкту:

```env
DB_PASSWORD=your_local_password
```

Запустити систему:

```bash
docker compose up -d --build
```

Адреси:

- Frontend: http://localhost:8081
- Backend API `api_a`: http://localhost:8080
- Backend API `api_b`: http://localhost:8082
- Swagger: http://localhost:8080/swagger

Перевірити контейнери:

```bash
docker compose ps
```

Переглянути журнали:

```bash
docker compose logs -f api_a api_b frontend db
```

Зупинити систему:

```bash
docker compose down
```

Дані PostgreSQL зберігаються в Docker volume postgres_data.

Не використовувати `docker compose down -v`, якщо потрібно зберегти дані.

## 7. Піковий сценарій навантаження

Потенційний сценарій високого навантаження — одночасне проходження тесту великою кількістю студентів.

Кожен студент виконує послідовність:

1. POST /api/tests/{testId}/attempts
2. Багаторазові PUT /api/attempts/{attemptId}/answers
3. POST /api/attempts/{attemptId}/submit
4. GET /api/attempts/{attemptId}/result

Найбільше навантаження створюють масові записи відповідей та одночасне завершення тестів.

## 8. Bottleneck Analysis

### 8.1. Збереження відповідей

Компонент: PUT /api/attempts/{id}/answers

Причина: велика кількість одночасних SQL-операцій запису, обмеження дискового I/O та пулу з'єднань.

Симптоми: зростання p99 latency, зниження RPS, очікування вільних з'єднань.

Можливе рішення: оптимізація SQL-запитів, індексація, налаштування пулу з'єднань.

### 8.2. Обчислення результатів

Компонент: POST /api/attempts/{id}/submit

Причина: одночасне завантаження відповідей і підрахунок балів для багатьох спроб.

Симптоми: підвищене використання CPU, зростання часу відповіді.

Можливе рішення: оптимізація запитів EF Core та вибірка тільки необхідних даних.

### 8.3. Єдиний сервер PostgreSQL

Компонент: PostgreSQL 17

Причина: усі операції читання та запису обслуговуються одним екземпляром БД.

Симптоми: I/O Wait, повільні SQL-запити, вичерпання доступних з'єднань.

Можливе рішення: індексація, оптимізація конфігурації БД, масштабування читання за потреби.

## 9. Розподіл роботи для лабораторної 2

| Частина | Відповідальність | Перевірка |
|---|---|---|
| Учасник А — стан і консистентність, пункти 2.1–2.3 | Аудит стану, транзакції та блокування рядка спроби в PostgreSQL, опис потоку запиту, вилучення демонстраційного статичного стану | Перевірено окремо до інтеграції скриптом `scripts/verify-vlad.ps1` |
| Учасник Б — розгортання і стійкість, пункти 2.4–2.6 | Два API-вузли, балансування Nginx, `X-Instance-ID`, сценарій втрати вузла, C4-схеми | `scripts/verify-stateless.ps1` у поточній конфігурації |

Обидві частини вже об'єднано. Повний сценарій лабораторної перевіряється командою `pwsh -NoProfile -File scripts/verify-stateless.ps1`.

## 10. Перевірка працездатності

Для захисту лабораторної потрібно продемонструвати:

- Запуск Docker Compose однією командою.
- Роботу інтерфейсу організатора.
- Створення та публікацію тесту.
- Проходження тесту студентом.
- Виконання щонайменше 5 REST API endpoints.
- Збереження даних після перезапуску PostgreSQL.

## 11. Лабораторна робота 2 — архітектура без локального бізнес-стану

### 11.1. Аудит стану

| Категорія | Дані або конструкція | Де зберігаються / висновок |
|---|---|---|
| Ephemeral / Local Safe | Локальні змінні запиту, DTO, обчислення балів, EF Core change tracker, журнали | Існують лише під час запиту; після нього не потрібні для наступного вузла. |
| Shared / Externalized | Тести, запитання, варіанти, спроби, відповіді, токени доступу, статус і результат | PostgreSQL; обидва API-вузли працюють з однією БД. |
| Critical Stateful Dependencies | Sticky sessions, серверні сесії, локальний кеш, singleton-колекції, локальні блокування, файловий стан | У бізнес-логіці відсутні. Демонстраційний `WeatherForecast` зі статичним масивом вилучено. |

Окремий Redis не потрібен: у системі немає серверного сесійного кешу, а PostgreSQL уже є спільним довговічним сховищем. `X-Attempt-Token` передається в кожному запиті до спроби; токен зберігається разом зі спробою в БД. `INSTANCE_ID` використовується лише для діагностики та повертається в заголовку `X-Instance-ID`.

Раніше `PUT /answers` і `POST /submit` читали та змінювали спробу незалежно. Паралельні запити могли одночасно створити відповідь або завершити спробу під час її оновлення. Тепер обидві операції виконуються в транзакції PostgreSQL із блокуванням рядка відповідної спроби (`SELECT ... FOR UPDATE`). Запити до однієї спроби впорядковуються між вузлами; обмеження унікальності `(TestAttemptId, QuestionId)` лишається додатковим захистом. Якщо API-процес завершується до commit, PostgreSQL відкочує транзакцію; після commit дані доступні другому вузлу.

### 11.2. Потік запиту збереження відповіді

1. Клієнт надсилає `PUT /api/attempts/{id}/answers`, заголовок `X-Attempt-Token` і JSON з `questionId`, `selectedOptionId`.
2. Будь-який API-вузол починає транзакцію, знаходить спробу за `id` і токеном у PostgreSQL та блокує її рядок до завершення транзакції.
3. Вузол перевіряє статус спроби й належність запитання та варіанта, читає поточну відповідь із БД.
4. Вузол додає або змінює відповідь, зберігає її та завершує транзакцію. У відповідь повертається `204` і заголовок `X-Instance-ID`.
5. Наступний запит, навіть на іншому вузлі, читає актуальні дані з PostgreSQL. Після запиту в процесі не залишається потрібного для продовження бізнес-стану.

Схеми C4 Container і C4 Component, а також послідовність запиту наведено в [docs/architecture.md](docs/architecture.md).

### 11.3. Запуск двох вузлів

У корені проєкту створіть `.env` за `.env.example` і задайте локальний пароль. Потім виконайте:

```powershell
docker compose up -d --build
docker compose ps
```

Сервіс `migrate` одноразово застосовує EF Core міграції перед запуском API. `api_a` слухає `localhost:8080`, `api_b` — `localhost:8082`, Nginx на `localhost:8081` розподіляє `/api/` між ними. Обидва вузли зібрані з однієї кодової бази та використовують одну БД. Перевірка вузлів:

```powershell
curl.exe -i http://localhost:8080/health
curl.exe -i http://localhost:8082/health
curl.exe -i http://localhost:8081/api/tests
```

Перші дві відповіді мають заголовки `X-Instance-ID: api-a` і `X-Instance-ID: api-b`. Для третьої заголовок показує вузол, обраний балансувальником.

### 11.4. Cross-instance consistency і втрата вузла

Скрипт створює окремий тест, виконує ланцюжок `POST → api_a`, `GET → api_b`, `PUT → api_b`, `GET → api_a`, створює запит до `api_a`, який очікує блокування рядка в PostgreSQL, аварійно зупиняє цей вузол під час запиту, читає збережену відповідь через Nginx на `api_b`, повертає `api_a`, завершує спробу на `api_b` і перевіряє результат на `api_a`:

```powershell
pwsh -File scripts/verify-stateless.ps1
```

Для перевірки тільки обміну даними між вузлами без зупинки:

```powershell
pwsh -File scripts/verify-stateless.ps1 -SkipFailureScenario
```

Скрипт перевіряє HTTP-статуси, `X-Instance-ID`, збережену відповідь і бал. Демонстраційні записи залишаються в БД для огляду. Зупинка `api_a` відбувається **під час** заблокованого запиту; незавершена транзакція при зупинці процесу відкочується PostgreSQL. Клієнт цього запиту може отримати мережеву помилку й має повторити ідемпотентну операцію. Повторне надсилання завершеної спроби повертає збережений результат.

Приклад ручної перевірки, якщо є опублікований тест із ID `$testId`:

```powershell
$started = curl.exe -s -X POST "http://localhost:8080/api/tests/$testId/attempts" | ConvertFrom-Json
$id = $started.attemptId
$token = $started.accessToken
curl.exe -i -H "X-Attempt-Token: $token" "http://localhost:8082/api/attempts/$id"
curl.exe -i -X PUT -H "Content-Type: application/json" -H "X-Attempt-Token: $token" -d '{"questionId":1,"selectedOptionId":1}' "http://localhost:8082/api/attempts/$id/answers"
curl.exe -i -H "X-Attempt-Token: $token" "http://localhost:8080/api/attempts/$id"
```

У ручному прикладі замініть ID запитання й варіанта на значення з відповіді `POST /attempts`.

### 11.5. Перевірка поточної версії

Після запуску Docker Compose перевірте збірку та повний сценарій на двох вузлах:

```powershell
dotnet build backend/OnlineTesting.Api/OnlineTesting.Api.csproj
pwsh -NoProfile -File scripts/verify-stateless.ps1
```

Наприкінці має з'явитися `PASS: cross-instance consistency and recovery`. Скрипт створює тест, зберігає відповідь через інший вузол, зупиняє `api_a` під час запиту, перевіряє доступність даних через `api_b`, відновлює `api_a` та перевіряє результат. Демонстраційні записи залишаються в PostgreSQL.

Для скрипта потрібен PowerShell 7. Якщо `pwsh` не знаходиться в PATH, вкажіть повний шлях до встановленого `pwsh.exe`. Скрипт `verify-vlad.ps1` збережено як перевірку окремої частини до інтеграції; у поточному Docker Compose немає сервісу `api`, який він перезапускає.
