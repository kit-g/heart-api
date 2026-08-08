# Database

Schema, migrations, and tests for the Heart of Yours Postgres database.

## Layout

```
database/
├── migrations/           # Forward-only SQL migrations, applied in filename order
├── tests/
│   ├── public/
│   │   ├── tables/       # pgtap structural tests — one per table
│   │   └── functions/    # pgtap behavior tests — one per function
│   └── archive/
│       └── tables/       # Tests for the archive schema
└── test_utils/
    └── helpers.sql       # Test data builders + JSON shape validators
```

## Migrations

Forward-only. Naming: `YYYY-MM-DD.<title>.sql`. Applied in lexical order — the date prefix orders them.

### Conventions

- **Forward-only.** No down migrations. If a migration is wrong, write a new one that reverses or amends it. (Exception: the dev DB can be wiped and replayed during heavy refactor windows.)
- **Idempotent where possible.** `DROP CONSTRAINT IF EXISTS` before `ADD CONSTRAINT` lets a migration re-run safely.
- **Tracking table:** `_schema_migrations(filename, applied_at)` is created idempotently by the runner. Each migration is applied in a transaction with its tracking row insert — atomic.

### Schema patterns

- **Single-roundtrip CTEs** for any operation that touches more than one table. Most write queries are `WITH _x AS (…), _y AS (…) SELECT …` — keeps logic in the planner.
- **`forbidden` sentinel** for read endpoints with auth checks: empty result = 404, single row with `forbidden = true` = 403, otherwise the data. See `_listWorkouts` / `_getTargetWorkout` in `api/lib/db/queries.dart` for the canonical shape.
- **`COALESCE` for partial updates**: `SET col = coalesce(@col, col)` — pass null for fields you want unchanged.
- **`BEFORE DELETE` triggers for snapshots**: cascade-deleted rows are still visible at trigger time. `_archive_workout` uses this to copy workout JSON into `archive.deleted_workouts` before the cascade fires.
- **Timestamps, where present, are `NOT NULL DEFAULT now()`** — defaults shouldn't be defeated by an explicit-null insert. Owner-level tables carry `created_at`; child rows that live and die with their parent (`workout_exercises`, `exercise_sets`, `template_exercises`, `template_exercise_sets`, `exercise_translations`) carry no timestamps of their own. Only `profiles` has `updated_at`, and nothing maintains it yet — don't read it as a change marker.

### Running

```bash
# Local: uses PGHOST etc. from your env (or auto-fetches Supabase creds from S3)
scripts/apply_migrations.sh
```

Behavior:
- If `PGHOST` is already set → uses your local connection
- Otherwise → fetches from S3.

The runner skips migrations already in `_schema_migrations` and applies the rest in order.

## Tests (pgtap)

Two styles depending on test type:

| Style            | Used for                            | Pattern                                                                                         |
|------------------|-------------------------------------|-------------------------------------------------------------------------------------------------|
| Inline `plan(N)` | Table tests — structural assertions | `BEGIN; SELECT plan(N); SELECT has_table(…); …; SELECT * FROM finish(); ROLLBACK;`              |
| `runtests()`     | Function tests — multi-step setups  | `CREATE OR REPLACE FUNCTION test_*() RETURNS SETOF TEXT …; SELECT * FROM runtests(); ROLLBACK;` |

Both wrap in `BEGIN; … ROLLBACK;` so each file is isolated.

### Coverage targets

For tables, exhaustive structural coverage is the bar:

- `has_table` + `columns_are`
- `col_type_is` per column
- `has_pk` + `col_is_pk`
- `col_not_null` per non-null column
- `col_default_is` per defaulted column
- `fk_ok` per foreign key
- `has_index` / `index_is_unique` for named indexes
- `col_is_unique` for unique constraints

For functions:
- `has_function` + `function_lang_is` + `function_returns`
- Edge case (empty/unknown id → expected default)
- Happy path (count + content)
- Ordering (insert out of order, assert sorted output)
- Shape (matches a `validate_format_*` JSON validator)
- For trigger functions: `trigger_is` to verify binding

### Test helpers

`test_utils/helpers.sql` is loaded once per session before pg_prove runs. Defines:

- **Builders** — `create_test_profile()`, `create_test_workout(_user_id)`, `create_test_exercise_set(_we_id, _set_order, _weight, _reps)`, etc. Minimal-arg, default values for everything else.
- **JSON shape validators** — `validate_format_exercise_set(_set JSONB) RETURNS SETOF BOOL`, etc. Each row asserts one constraint (key count, type per field, optional null). Use as `TRUE = ALL (SELECT validate_format_x(json))`.

The helpers are `CREATE OR REPLACE` so re-loads are idempotent.

### Running

```bash
# Loads helpers, then runs pg_prove against tests/**/*.sql.
# Env: the IDE run-config vars (DB_HOST_URL, DB_HOST_PORT, DB_USER, DB_PASSWORD)
# win when set; otherwise the standard PG* vars, defaulting to localhost/heart.
# The suite seeds and mutates data — never point it at the shared Supabase instance.
scripts/db_tests.sh
```

No native Postgres? The repo ships a containerized one (Postgres 17 + pgtap,
matching CI — see `compose.yaml`):

```bash
make db-up      # build + start, waits until healthy
make test-db    # apply migrations + run the suite against it
make db-down    # stop; data persists in the named volume
make db-reset   # drop the volume, replay every migration from zero —
                # required after editing an already-applied migration
make db-seed    # migrations + exercise library from content/ (local, no AWS);
                # idempotent — the deterministic way to repopulate after a reset
# 5432 taken by a native install: HEART_DB_PORT=5433 make db-up, then export PGPORT=5433
```

CI runs the exact same script against an ephemeral Postgres provisioned on the runner — see `.github/workflows/deploy-api.yml` (`db-test` job).

### Adding a table

1. Migration: `database/migrations/YYYY-MM-DD.<table>.sql` with `DROP TABLE IF EXISTS … CASCADE; CREATE TABLE …;`
2. Test: `database/tests/public/tables/<table>.sql` covering everything in the table.
3. Helper (optional): `create_test_<table>(...)` builder in `test_utils/helpers.sql` if other tests need to stage rows.

### Adding a function

1. Migration: `database/migrations/YYYY-MM-DD.<feature>-functions.sql`
2. Test: `database/tests/public/functions/<function>.sql` using `runtests()` style — define `test_*()` plpgsql functions, end with `SELECT * FROM runtests();`
3. JSON validator (optional): if the function returns JSON, add `validate_format_<thing>` to `helpers.sql`.

### Identifier-length gotcha

Postgres truncates identifiers (function names, table names) to 63 characters. Test functions like `test__some_long_thing_returns_empty_array_for_unknown_workout()` get truncated, producing a `NOTICE` and shadowing other tests. Keep test function names short — abbreviate the function-under-test in the name (`test__we_*` for `_workout_exercises`).
