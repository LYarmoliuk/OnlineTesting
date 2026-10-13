
# ER-діаграма OnlineTesting

## Доменна модель

Система містить п'ять основних сутностей:

- Test — тест, створений організатором.
- Question — запитання тесту.
- AnswerOption — можливий варіант відповіді.
- TestAttempt — спроба проходження тесту студентом.
- StudentAnswer — відповідь студента на запитання.

## ER Diagram

```mermaid
erDiagram
    Tests ||--o{ Questions : contains
    Questions ||--o{ AnswerOptions : has
    Tests ||--o{ TestAttempts : has
    TestAttempts ||--o{ StudentAnswers : contains
    Questions ||--o{ StudentAnswers : answered_in
    AnswerOptions ||--o{ StudentAnswers : selected_in

    Tests {
        int Id PK
        string Title
        string Description
        boolean IsPublished
    }

    Questions {
        int Id PK
        int TestId FK
        string Text
        int Order
        int Points
    }

    AnswerOptions {
        int Id PK
        int QuestionId FK
        string Text
        boolean IsCorrect
    }

    TestAttempts {
        int Id PK
        int TestId FK
        string AccessToken
        string Status
        datetime StartedAt
        datetime CompletedAt
        int Score
    }

    StudentAnswers {
        int Id PK
        int AttemptId FK
        int QuestionId FK
        int SelectedOptionId FK
    }
```

## Зв'язки між сутностями

| Зв'язок | Кардинальність | Опис |
|---|---|---|
| Test → Question | 1:N | Один тест містить багато запитань |
| Question → AnswerOption | 1:N | Одне запитання має багато варіантів |
| Test → TestAttempt | 1:N | Один тест може мати багато спроб |
| TestAttempt → StudentAnswer | 1:N | Одна спроба містить відповіді |
| Question → StudentAnswer | 1:N | На запитання можуть відповідати в різних спробах |
| AnswerOption → StudentAnswer | 1:N | Один варіант може бути обраний у багатьох спробах |

## Відповідальність учасника №2

Учасник №2 реалізував:

- TestAttempt — зберігання спроб тестування.
- StudentAnswer — зберігання відповідей студентів.
- REST API для проходження тестів.
- Автоматичне обчислення результатів.

Сутності Tests, Questions та AnswerOptions використовуються як залежності модуля проходження тестів.
## Документація модуля учасника №2

- [ER-діаграма бази даних](docs/er-diagram.md)
- [Модуль проходження тестів](docs/student-module.md)
- [Архітектура системи](docs/architecture.md)