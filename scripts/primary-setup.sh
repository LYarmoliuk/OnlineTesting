#!/usr/bin/env bash
set -euo pipefail
psql -U app -d postgres -v ON_ERROR_STOP=1 -v pass="$POSTGRES_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') \gexec
SQL
if ! grep -q '^host replication replicator ' "$PGDATA/pg_hba.conf"; then
  echo 'host replication replicator 0.0.0.0/0 scram-sha-256' >> "$PGDATA/pg_hba.conf"
fi
psql -U app -d postgres -c 'SELECT pg_reload_conf();'
