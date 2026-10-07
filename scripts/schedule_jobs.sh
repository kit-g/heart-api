#!/usr/bin/env bash
# Declare Heart's pg_cron jobs from database/cron/jobs.sql.
#
# Connection: as apply_migrations.sh. pg_cron lives in the `postgres` database,
# so this connects there; each job runs in the app's database ($PGDATABASE,
# heart by default).
#
# Without pg_cron the jobs can't be declared: this warns (loudly in CI) and
# exits 0, so a deploy isn't blocked. Until pg_cron is enabled, nothing in
# jobs.sql runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DB_DIR="$SCRIPT_DIR/../database"

if [ -z "${PGHOST:-}" ]; then
  CREDS_FILE="${CREDS_FILE:-/tmp/supabase.json}"
  if [ ! -f "$CREDS_FILE" ]; then
    echo ">> Fetching Supabase credentials from S3"
    aws s3 cp "s3://583168578067-ca-central-1-static/secrets/supabase.json" "$CREDS_FILE" >/dev/null
  fi
  export PGHOST="$(jq -r .host "$CREDS_FILE")"
  export PGPORT="$(jq -r .port "$CREDS_FILE")"
  export PGUSER="$(jq -r .user "$CREDS_FILE")"
  export PGPASSWORD="$(jq -r .password "$CREDS_FILE")"
fi
APP_DB="${PGDATABASE:-heart}"

if [ -z "$(psql -d postgres -tAc "SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'")" ]; then
  echo "::warning title=pg_cron is not enabled::Scheduled database jobs (database/cron/jobs.sql) were not declared and will not run. Enable pg_cron on this server."
  exit 0
fi

psql -d postgres -v ON_ERROR_STOP=1 -v db="$APP_DB" --quiet -f "$DB_DIR/cron/jobs.sql" >/dev/null
echo ">> Scheduled jobs declared, running in $APP_DB:"
psql -d postgres -tAc "SELECT jobname, schedule, database FROM cron.job ORDER BY jobname"
