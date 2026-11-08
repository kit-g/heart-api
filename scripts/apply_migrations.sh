#!/usr/bin/env bash
# Apply any unapplied migrations from database/migrations/.
#
# Connection:
#   - If PGHOST is already set, uses the existing PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE.
#     (CI db-test job sets these for the ephemeral local Postgres.)
#   - Otherwise, fetches Supabase credentials from
#     s3://583168578067-ca-central-1-static/secrets/supabase.json and points psql at them.
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
    aws s3 cp "s3://583168578067-ca-central-1-static/secrets/supabase.json" "$CREDS_FILE" >/dev/null
  fi
  export PGHOST="$(jq -r .host "$CREDS_FILE")"
  export PGPORT="$(jq -r .port "$CREDS_FILE")"
  export PGUSER="$(jq -r .user "$CREDS_FILE")"
  export PGPASSWORD="$(jq -r .password "$CREDS_FILE")"
  export PGDATABASE="${PGDATABASE:-heart}"
fi

# A remote migration connection must authenticate the server too. Keep the
# literal loopback addresses for the credential-free local/CI database.
case "$PGHOST" in
  localhost|127.0.0.1|::1) ;;
  *)
    export PGSSLMODE=verify-full
    export PGSSLROOTCERT="${PGSSLROOTCERT:-$SCRIPT_DIR/../api/bin/supabase-ca.crt}"
    ;;
esac

echo ">> Ensuring _schema_migrations table"
psql -v ON_ERROR_STOP=1 --quiet <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

cd "$DB_DIR/migrations"

# The name is the order. Same-day files used to fall back on their slug's
# alphabetical order, which held by luck (2026-10-14, 2026-11-01): a file dated
# after 2026-11-04 carries the UTC time it was written, YYYY-MM-DD.HHMM.slug.sql,
# and no two share that prefix. Files up to then keep their names, since a
# renamed file runs again. Byte order, so no locale reorders punctuation.
migrations=$(LC_ALL=C ls -1 *.sql | LC_ALL=C sort)
bad=0
prefixes=""
for f in $migrations; do
  if [[ ! "$f" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})(\.([0-9]{4}))?\.[a-z0-9]+(-[a-z0-9]+)*\.sql$ ]]; then
    echo "!! $f: name it YYYY-MM-DD.HHMM.short-name.sql" >&2
    bad=1
    continue
  fi
  day="${BASH_REMATCH[1]}"
  time="${BASH_REMATCH[3]}"
  if [[ "$day" > "2026-11-04" ]]; then
    if [ -z "$time" ] || [ "${time:0:2}" -gt 23 ] || [ "${time:2:2}" -gt 59 ]; then
      echo "!! $f: a migration after 2026-11-04 is named YYYY-MM-DD.HHMM.short-name.sql (UTC)" >&2
      bad=1
    elif [[ " $prefixes " == *" $day.$time "* ]]; then
      echo "!! $f: another migration is already $day.$time; take the next minute" >&2
      bad=1
    fi
    prefixes="$prefixes $day.$time"
  fi
done
if [ "$bad" -ne 0 ]; then
  echo ">> Migration names refused; nothing applied" >&2
  exit 1
fi

applied_count=0
skipped_count=0

for f in $migrations; do
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
