#!/usr/bin/env bash
# Apply any unapplied migrations from database/migrations/.
#
# Connection:
#   - If PGHOST is already set, uses the existing PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE.
#     (CI db-test job sets these for the ephemeral local Postgres.)
#   - Otherwise, fetches Supabase credentials from
#     s3://583168578067-us-east-2-static/secrets/supabase.json and points psql at them.
#
# Tracking: a `_schema_migrations` table is created idempotently. Each migration
# applied within a transaction along with its tracking row, so it's all-or-nothing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DB_DIR="$SCRIPT_DIR/../database"

if [ -z "${PGHOST:-}" ]; then
  CREDS_FILE="${CREDS_FILE:-/tmp/supabase.json}"
  if [ ! -f "$CREDS_FILE" ]; then
    echo ">> Fetching Supabase credentials from S3"
    aws s3 cp "s3://583168578067-us-east-2-static/secrets/supabase.json" "$CREDS_FILE" >/dev/null
  fi
  export PGHOST="$(jq -r .host "$CREDS_FILE")"
  export PGPORT="$(jq -r .port "$CREDS_FILE")"
  export PGUSER="$(jq -r .user "$CREDS_FILE")"
  export PGPASSWORD="$(jq -r .password "$CREDS_FILE")"
  export PGDATABASE="${PGDATABASE:-heart}"
fi

echo ">> Ensuring _schema_migrations table"
psql -v ON_ERROR_STOP=1 --quiet <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

cd "$DB_DIR/migrations"
applied_count=0
skipped_count=0

for f in $(ls -1 *.sql | sort); do
  is_applied=$(psql -tAc "SELECT 1 FROM _schema_migrations WHERE filename = '$f'")
  if [ -z "$is_applied" ]; then
    echo ">> Applying $f"
    psql --single-transaction -v ON_ERROR_STOP=1 --quiet <<SQL
\i $f
INSERT INTO _schema_migrations (filename) VALUES ('$f');
SQL
    applied_count=$((applied_count + 1))
  else
    skipped_count=$((skipped_count + 1))
  fi
done

echo ">> Migrations: $applied_count applied, $skipped_count already up to date"
