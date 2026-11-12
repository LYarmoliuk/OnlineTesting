#!/usr/bin/env bash
set -euo pipefail
for host in db db_shard_b; do
  PGPASSWORD="$DB_PASSWORD" psql -h "$host" -U app -d online_testing -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS lab7_events (
  strategy text NOT NULL CHECK (strategy IN ('single', 'legacy', 'bucket')),
  student_id varchar(64) NOT NULL,
  attempt_id bigint NOT NULL,
  event_id uuid NOT NULL,
  event_type varchar(64) NOT NULL,
  payload varchar(512) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (strategy, student_id, attempt_id, event_id)
);
CREATE INDEX IF NOT EXISTS lab7_events_search_idx
  ON lab7_events (strategy, created_at DESC);
CREATE INDEX IF NOT EXISTS lab7_events_type_idx
  ON lab7_events (strategy, event_type, created_at DESC);
ALTER TABLE lab7_events DROP CONSTRAINT IF EXISTS lab7_events_strategy_check;
ALTER TABLE lab7_events ADD CONSTRAINT lab7_events_strategy_check
  CHECK (strategy IN ('single', 'legacy', 'bucket'));
SQL
done
