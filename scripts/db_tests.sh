#!/usr/bin/env bash
# Loads the pgtap test helpers and runs the database suite.
#
# Accepts either the IDE run-config vars (DB_HOST_URL, DB_HOST_PORT, DB_USER,
# DB_PASSWORD — they win when set) or the standard PG* env vars that
# apply_migrations.sh and CI use. Defaults target the local dev database;
# the suite seeds and mutates data, so it must never point at the shared
# Supabase instance.
#
# CI (deploy-api.yml) calls this script and tees its TAP output into the
# test-summary report.
set -euo pipefail

if [ -n "${DB_USER:-}" ]; then export PGUSER="$DB_USER"; fi
if [ -n "${DB_PASSWORD:-}" ]; then export PGPASSWORD="$DB_PASSWORD"; fi
export PGHOST="${DB_HOST_URL:-${PGHOST:-localhost}}"
export PGPORT="${DB_HOST_PORT:-${PGPORT:-5432}}"
export PGDATABASE="${PGDATABASE:-heart}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DB_DIR="$SCRIPT_DIR/../database"

psql --quiet --set ON_ERROR_STOP=1 -f "$DB_DIR/test_utils/helpers.sql" > /dev/null

cd "$DB_DIR"
# find, not tests/**/*.sql: globstar needs bash 4+, and macOS ships 3.2 —
# under old bash the glob silently matches only one level deep.
find tests -name '*.sql' | sort | xargs pg_prove --quiet
