# Lab 6 — топологія PostgreSQL

```mermaid
flowchart LR
  Browser --> Nginx --> API[api_a / api_b / api_c]
  API -->|writes, strict reads, fallback| Primary[(PostgreSQL primary: db)]
  API -->|eventual catalog reads| Replica[(PostgreSQL read-only: db_replica)]
  Primary -->|asynchronous WAL streaming| Replica
  API -->|cache-aside| Redis[(Redis)]
```

Міграції EF Core й усі транзакції виконуються на primary. Replica обслуговує каталог і список запитань. `ReplicaReadService` виконує fallback до primary при недоступності replica. Критичні читання залишаються на primary, щоб забезпечити read-after-write. Автоматичний promotion replica не налаштовано, тому при втраті primary записи блокуються, а eventual reads залишаються доступними.
