#!/usr/bin/env bash
set -euo pipefail
export PGDATA=/var/lib/postgresql/data
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"
printf 'db:5432:*:replicator:%s\n' "$PGPASSWORD" > /var/lib/postgresql/.pgpass
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  until gosu postgres pg_basebackup -h db -U replicator -D "$PGDATA" -R -X stream -P; do
    find "$PGDATA" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    sleep 2
  done
fi
exec gosu postgres postgres -D "$PGDATA" -c hot_standby=on
