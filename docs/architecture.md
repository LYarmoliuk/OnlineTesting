# Архітектура OnlineTesting

## 1. Загальний опис

OnlineTesting — вебсистема для створення та проходження онлайн-тестів.

Система складається з frontend, двох однакових API-контейнерів, одноразового контейнера міграцій та PostgreSQL:
- Frontend — Vue 3 + TypeScript.
- Backend API — ASP.NET Core 10, вузли `api_a` і `api_b`.
- Migration — застосування EF Core міграцій перед стартом API.
- Database — PostgreSQL 17.

Усі компоненти можуть запускатися за допомогою Docker Compose.

## 2. C4 Container Diagram

```mermaid
flowchart TB
    Student["Студент"]
    Organizer["Організатор"]

    subgraph OnlineTesting["OnlineTesting"]
        Frontend["Frontend<br/>Vue 3 + TypeScript<br/>Nginx"]
        APIA["API api_a<br/>ASP.NET Core 10<br/>EF Core"]
        APIB["API api_b<br/>ASP.NET Core 10<br/>EF Core"]
        Migration["migrate<br/>EF Core migrations"]
        DB[("PostgreSQL 17<br/>Tests, Questions,<br/>TestAttempts, StudentAnswers")]
    end

    Student -->|"Проходить тести"| Frontend
    Organizer -->|"Керує тестами"| Frontend
    Frontend -->|"Nginx /api без sticky sessions"| APIA
    Frontend -->|"Nginx /api без sticky sessions"| APIB
    APIA -->|"EF Core / SQL"| DB
    APIB -->|"EF Core / SQL"| DB
    Migration -->|"Схема БД"| DB
```

### Пояснення

**Frontend** відображає інтерфейс користувача та надсилає HTTP-запити до API.

**Backend API** обробляє бізнес-логіку на двох взаємозамінних вузлах. Кожен вузол повертає заголовок `X-Instance-ID`.

**PostgreSQL** зберігає тести, запитання, варіанти відповідей, спроби проходження та відповіді студентів.

Nginx обслуговує frontend і розподіляє запити `/api/` між `api_a` та `api_b`. Обидва вузли використовують одну БД.

## 3. C4 Component Diagram — модуль проходження тестів

```mermaid
flowchart TB
    StudentUI["StudentTestView.vue<br/>Інтерфейс студента"]
    ApiService["api.ts<br/>HTTP-запити"]

    subgraph BackendA["API instance api_a"]
        ControllerA["AttemptsController<br/>REST + токен"]
        ScoringA["Оцінювання"]
        EFA["Scoped AppDbContext<br/>транзакція + row lock"]
    end

    subgraph BackendB["API instance api_b"]
        ControllerB["AttemptsController<br/>REST + токен"]
        ScoringB["Оцінювання"]
        EFB["Scoped AppDbContext<br/>транзакція + row lock"]
    end

    Database[("PostgreSQL<br/>TestAttempts<br/>StudentAnswers")]

    StudentUI -->|"Дії студента"| ApiService
    ApiService -->|"Nginx /api + X-Attempt-Token"| ControllerA
    ApiService -->|"Nginx /api + X-Attempt-Token"| ControllerB
    ControllerA --> ScoringA
    ControllerB --> ScoringB
    ControllerA --> EFA
    ControllerB --> EFB
    ScoringA --> EFA
    ScoringB --> EFB
    EFA -->|"SQL"| Database
    EFB -->|"SQL"| Database
```

### Компоненти модуля учасника №2

**StudentTestView.vue** — інтерфейс проходження тесту, вибору відповідей і перегляду результату.

**api.ts** — клієнтські функції для звернення до REST API.

**AttemptsController** — створення спроб, перевірка токенів, збереження відповідей, завершення тестування та отримання результатів.

**Логіка оцінювання** — обчислення набраних балів за правильними відповідями. Це логічний компонент усередині backend, а не обов'язково окремий клас.

**EF Core DbContext** — доступ до таблиць PostgreSQL через сутності.

## 4. Основний сценарій взаємодії

```mermaid
sequenceDiagram
    actor Student as Студент
    participant UI as Vue Frontend
    participant APIA as API api_a
    participant APIB as API api_b
    participant DB as PostgreSQL

    Student->>UI: Почати тест
    UI->>APIA: POST /api/tests/{testId}/attempts
    APIA->>DB: Створити TestAttempt
    DB-->>APIA: Збережена спроба
    APIA-->>UI: attemptId, token, запитання, X-Instance-ID

    Student->>UI: Вибрати відповідь
    UI->>APIB: PUT /api/attempts/{id}/answers + X-Attempt-Token
    APIB->>DB: BEGIN, SELECT TestAttempt FOR UPDATE
    DB-->>APIB: Статус і контекст спроби
    APIB->>DB: INSERT або UPDATE StudentAnswer, COMMIT
    APIB-->>UI: 204 + X-Instance-ID

    UI->>APIA: GET /api/attempts/{id} + X-Attempt-Token
    APIA->>DB: Прочитати актуальну відповідь
    DB-->>APIA: StudentAnswer
    APIA-->>UI: Збережений вибір
    Student->>UI: Завершити тест
    UI->>APIB: POST /api/attempts/{id}/submit
    APIB->>DB: BEGIN, SELECT TestAttempt FOR UPDATE
    APIB->>DB: Прочитати відповіді, зберегти Score, COMMIT
    APIB-->>UI: Результат тесту
    UI-->>Student: Показати бали
```

## 5. Розгортання

Для запуску використовується команда:

```powershell
docker compose up -d --build
```

Основні адреси:
- Frontend: `http://localhost:8081`
- Backend API: `http://localhost:8080`
- Другий API-вузол: `http://localhost:8082`
- PostgreSQL: `localhost:5432`

Контейнери використовують спільну Docker-мережу `testing-network`.

Дані PostgreSQL зберігаються в Docker volume `postgres_data`.

## 6. Архітектурні рішення

1. **Два stateless API-вузли.** Вузол не зберігає бізнес-стан між запитами; кожен запит може обробити довільний вузол.
2. **REST API.** Забезпечує зрозумілу взаємодію через HTTP та JSON.
3. **Entity Framework Core.** Спрощує роботу з даними та підтримує міграції структури БД.
4. **PostgreSQL.** Забезпечує реляційне зберігання пов'язаних сутностей.
5. **Docker Compose.** Дозволяє відтворити середовище запуску однією командою.
6. **Токен доступу до спроби.** Обмежує доступ до відповідей і результатів конкретної спроби.
7. **Транзакції та row lock PostgreSQL.** Узгоджують збереження відповіді й завершення спроби між процесами та забезпечують rollback незавершеної операції при втраті вузла.

## 7. Розподіл роботи лабораторної 2

Учасник А виконав аудит стану та забезпечив узгоджене збереження відповідей і завершення спроб через транзакції та блокування рядка в PostgreSQL (пункти 2.1–2.3).

Учасник Б додав два API-вузли, ідентифікацію `X-Instance-ID`, балансування Nginx, сценарій втрати вузла та оновив архітектурні схеми (пункти 2.4–2.6). Усі компоненти вже об'єднано в поточній конфігурації.
