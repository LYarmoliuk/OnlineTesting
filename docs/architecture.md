# Архітектура OnlineTesting

## 1. Загальний опис

OnlineTesting — вебсистема для створення та проходження онлайн-тестів.

Система складається з трьох основних контейнерів:
- Frontend — Vue 3 + TypeScript.
- Backend API — ASP.NET Core 10.
- Database — PostgreSQL 17.

Усі компоненти можуть запускатися за допомогою Docker Compose.

## 2. C4 Container Diagram

```mermaid
flowchart TB
    Student["Студент"]
    Organizer["Організатор"]

    subgraph OnlineTesting["OnlineTesting"]
        Frontend["Frontend<br/>Vue 3 + TypeScript<br/>Nginx"]
        API["Backend API<br/>ASP.NET Core 10<br/>EF Core"]
        DB[("PostgreSQL 17<br/>Tests, Questions,<br/>TestAttempts, StudentAnswers")]
    end

    Student -->|"Проходить тести"| Frontend
    Organizer -->|"Керує тестами"| Frontend
    Frontend -->|"HTTP / REST / JSON"| API
    API -->|"EF Core / SQL"| DB
```

### Пояснення

**Frontend** відображає інтерфейс користувача та надсилає HTTP-запити до API.

**Backend API** обробляє бізнес-логіку: керування тестами, створення спроб, збереження відповідей та обчислення результатів.

**PostgreSQL** зберігає тести, запитання, варіанти відповідей, спроби проходження та відповіді студентів.

Nginx обслуговує frontend і передає запити `/api/` до backend-контейнера.

## 3. C4 Component Diagram — модуль проходження тестів

```mermaid
flowchart TB
    StudentUI["StudentTestView.vue<br/>Інтерфейс студента"]
    ApiService["api.ts<br/>HTTP-запити"]

    subgraph Backend["ASP.NET Core API"]
        AttemptsController["AttemptsController<br/>REST endpoints"]
        Scoring["Логіка оцінювання<br/>Перевірка відповідей і Score"]
        EF["EF Core DbContext<br/>Доступ до сутностей"]
    end

    Database[("PostgreSQL<br/>TestAttempts<br/>StudentAnswers")]

    StudentUI -->|"Дії студента"| ApiService
    ApiService -->|"HTTP + X-Attempt-Token"| AttemptsController
    AttemptsController -->|"Завершення спроби"| Scoring
    AttemptsController -->|"Читання / запис"| EF
    Scoring -->|"Дані відповідей і балів"| EF
    EF -->|"SQL"| Database
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
    participant API as ASP.NET Core API
    participant DB as PostgreSQL

    Student->>UI: Почати тест
    UI->>API: POST /api/tests/{testId}/attempts
    API->>DB: Створити TestAttempt
    DB-->>API: Збережена спроба
    API-->>UI: attemptId, token, запитання

    Student->>UI: Вибрати відповідь
    UI->>API: PUT /api/attempts/{id}/answers
    API->>DB: Зберегти StudentAnswer
    API-->>UI: Підтвердження

    Student->>UI: Завершити тест
    UI->>API: POST /api/attempts/{id}/submit
    API->>DB: Прочитати відповіді та правильні варіанти
    API->>API: Обчислити Score
    API->>DB: Зберегти результат
    API-->>UI: Результат тесту
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
- PostgreSQL: `localhost:5432`

Контейнери використовують спільну Docker-мережу `testing-network`.

Дані PostgreSQL зберігаються в Docker volume `postgres_data`.

## 6. Архітектурні рішення

1. **Поділ frontend і backend.** Дозволяє незалежно розробляти інтерфейс і серверну логіку.
2. **REST API.** Забезпечує зрозумілу взаємодію через HTTP та JSON.
3. **Entity Framework Core.** Спрощує роботу з даними та підтримує міграції структури БД.
4. **PostgreSQL.** Забезпечує реляційне зберігання пов'язаних сутностей.
5. **Docker Compose.** Дозволяє відтворити середовище запуску однією командою.
6. **Токен доступу до спроби.** Обмежує доступ до відповідей і результатів конкретної спроби.

## 7. Відповідальність учасника №2

Учасник №2 відповідає за компонент проходження тестів, включно з REST endpoints, сутностями TestAttempt і StudentAnswer, логікою оцінювання, студентським інтерфейсом та перевіркою інтеграції з базою даних.

Інші компоненти системи відображені на загальній діаграмі для розуміння взаємодії між модулями.
