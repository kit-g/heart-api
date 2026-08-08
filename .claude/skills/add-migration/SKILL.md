---
name: add-migration
description: Add a database migration and its pgtap test to database/. Use whenever creating or altering a table/function/index. Encodes the file-naming, house SQL style, snake_case rule, the two pgtap test forms (tables use plan(N); functions use test__*/runtests()), and why editing an already-applied migration silently does nothing. Triggers: "add a migration", "new table", "alter table", "add a column", "new DB function".
---

# Adding a migration + pgtap test

The migration runner applies `database/migrations/*.sql` in filename sort order, tracked in `_schema_migrations`. Tests live in `database/tests/**/*.sql` and run under `pg_prove`.

## Naming

`database/migrations/YYYY-MM-DD.short-name.sql` — date-prefixed (sorts chronologically = apply order), kebab-case slug. Use today's date. If two migrations share a date, the slug breaks the tie alphabetically — name them so the intended order holds.

### Editing an already-applied migration is a silent no-op

`_schema_migrations` is keyed on **filename**. `apply_migrations.sh` skips any file already recorded there — so if you edit a migration that has been applied, nothing runs and the runner still prints success. You then "verify" against a schema that never got your change.

Before editing an existing migration file, check:

```bash
psql -d heart -tAc "SELECT 1 FROM _schema_migrations WHERE filename = '<file>.sql'"
```

- **Empty** → not applied here, safe to edit freely (still unsafe if it shipped to a deployed env).
- **Non-empty** → do NOT edit it. Write a new migration. If it is unshipped and you want to consolidate, reset first (below).

Renaming a migration file is the same hazard in reverse: the new name is unrecorded, so it re-runs. That is fine only if the body is idempotent.

## House style (match existing migrations)

- Lead with `DROP TABLE IF EXISTS <name>;` then `CREATE TABLE IF NOT EXISTS` — migrations are written to be re-runnable in dev. (Don't drop in a migration that alters an existing populated table in a way you can't reproduce — for ALTERs, use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.)
- **snake_case** column names always (this is the DB layer).
- `id UUID PRIMARY KEY DEFAULT uuidv7()` for new entity tables (sortable by creation).
- `TIMESTAMPTZ NOT NULL DEFAULT now()` for timestamps.
- FKs: `REFERENCES <table> ON DELETE CASCADE` where the child is owned.
- Polymorphic "exactly one of N" → separate nullable FK columns + a `CHECK ((a IS NOT NULL)::int + (b IS NOT NULL)::int + ... = 1)`. (See `comments`.)
- Partial indexes for the nullable-FK columns: `CREATE INDEX ... WHERE col IS NOT NULL`.
- `COMMENT ON TABLE/COLUMN/CONSTRAINT` for every object — the codebase documents schema inline.
- Postgres truncates identifiers to 63 chars — keep index/constraint names short.

## pgtap test

pgtap covers **schema, signatures, and the behavior of database-side functions and triggers**. It does **not** cover the SQL the API runs — that lives in `api/lib/db/queries.dart` and is covered by `db`-tagged Dart integration tests (see the `add-endpoint` skill).

There are **two forms**, chosen by what you are testing. They are not interchangeable — the table form is a flat script with an explicit plan; the function form is pgtap's xUnit runner with no plan at all. Pick by directory:

| you added                        | file                                         | form                     |
|----------------------------------|----------------------------------------------|--------------------------|
| table, column, index, constraint | `database/tests/<schema>/tables/<table>.sql` | flat + `plan(N)`         |
| function or trigger              | `database/tests/<schema>/functions/<fn>.sql` | `test__*` + `runtests()` |

---

### Tables — flat assertions with `plan(N)`

```sql
BEGIN;
SELECT plan(N);          -- N = exact number of assertions below
SELECT has_table('public'::name, '<table>'::name);
SELECT columns_are('public', '<table>', ARRAY[ ... ]);   -- every column
SELECT col_type_is('public'::name, '<table>'::name, '<col>'::name, '<type>'::name);
SELECT has_pk(...); SELECT col_is_pk(...);
SELECT col_not_null(...);   -- one per NOT NULL column
SELECT col_default_is('public', '<table>', '<col>', '<rendered-default>', '<desc>');
SELECT fk_ok('public', '<table>', '<fk_col>', 'public', '<parent>', 'id');  -- one per FK
SELECT has_index(...); SELECT index_is_unique(...);
SELECT * FROM finish();
ROLLBACK;
```

**`plan(N)` must equal the exact count of `SELECT`-assertion calls.** Count them after writing, don't estimate. `columns_are` is ONE assertion regardless of column count; each `col_type_is`/`col_not_null`/`fk_ok`/`has_index` is one each. If `pg_prove` says "looks like you planned N but ran M", fix the number — don't add filler assertions to reach it.

When you add a column to an existing table, three things change in its test: the `columns_are` array, a new `col_type_is`, and `plan(N)`. Adding an index adds a `has_index` and another to the plan.

Assertion-specific notes:

- `col_default_is` wants the **rendered** default exactly as Postgres stores it: `uuidv7()`, `now()`, `'en'` (text), `'{}'::jsonb`. When unsure, check an existing table's test or query `information_schema.columns`.
- `col_type_is` type names: `uuid`, `text`, `integer`, `boolean`, `jsonb`, `timestamp with time zone` (not `timestamptz`), `real`.

---

### Functions and triggers — `test__*` + `runtests()`

No `plan(N)`. Each test is a named function returning `SETOF TEXT`, one `RETURN NEXT` per assertion; `runtests()` discovers every `test__*` in the transaction and counts them for you. Group related assertions into one test function with a descriptive name — the name is what `pg_prove` reports.

```sql
BEGIN;

CREATE OR REPLACE FUNCTION test__<fn>_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '<fn>'::name, ARRAY ['jsonb']);
    RETURN NEXT function_returns('public'::name, '<fn>'::name, ARRAY ['jsonb'], 'jsonb');
    RETURN NEXT function_lang_is('public'::name, '<fn>'::name, ARRAY ['jsonb'], 'sql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__<fn>_does_the_thing() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _w_id    UUID;
BEGIN
    _user_id := create_test_profile();

    -- precondition: nothing exists yet for what this test is about to create
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');

    _w_id := create_test_workout(_user_id => _user_id, _name => 'archive me');
    RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id), 0::bigint, 'not archived yet');

    DELETE FROM workouts WHERE id = _w_id;

    RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id), 1::bigint, 'archived on delete');
    RETURN NEXT ok((SELECT deleted_at FROM archive.deleted_workouts WHERE id = _w_id) IS NOT NULL, 'deleted_at set');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
```

#### Assert the table is empty before creating entities in it

A test that seeds rows and then counts them is only meaningful from a known-empty start. Without the precondition, leftover data turns a real failure into a confusing off-by-N — or masks one entirely — and the message you get is "expected 1, have 383" rather than "the database was dirty".

**Scope the emptiness assertion to what this test is about to create**, not to the whole table. A bare `count(*) FROM <table>` only holds on a fresh CI database: `archive.deleted_workouts` carries 382 rows on a working dev box, and `exercises` holds the whole synced library. Assert on the slice you own:

```sql
-- good: the slice this test creates
RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');
RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id), 0::bigint, 'not archived yet');

-- bad: passes in CI, fails on any dev machine with history
RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts), 0::bigint, 'archive starts empty');
```

Seed the owning row first (`create_test_profile()`), then assert emptiness scoped by its id, then create. One assertion per table the test writes into.

#### Signature assertions

`has_function` / `function_returns` / `function_lang_is` take an **optional argument-type array**, and the two forms are not interchangeable:

```sql
-- function WITH arguments: pass the type array, so an overload or a changed
-- signature is actually caught rather than matching on name alone
RETURN NEXT has_function('public'::name, '_workout_exercises'::name, ARRAY ['uuid']);
RETURN NEXT function_returns('public'::name, '_workout_exercises'::name, ARRAY ['uuid'], 'jsonb');
RETURN NEXT function_lang_is('public'::name, '_workout_exercises'::name, ARRAY ['uuid'], 'sql'::name);

-- zero-arg function: OMIT the array entirely. `ARRAY[]::name[]` does NOT match
-- and the assertion fails with "function does not exist".
RETURN NEXT has_function('public'::name, 'uuidv7'::name);
RETURN NEXT function_returns('public'::name, 'uuidv7'::name, 'uuid');
```

`function_lang_is` wants the language as stored: `sql`, `plpgsql`.

#### Other notes

- Seed via `database/test_utils/helpers.sql` — `create_test_profile`, `create_test_exercise`, `create_test_workout`, `create_test_workout_exercise`, `create_test_exercise_set`, `create_test_template`, `create_test_template_exercise`, `create_test_template_set`. Read the signatures there rather than guessing parameter order; most have defaults and are best called with named args (`_user_id =>`).
- Group related assertions into one `test__*` function with a descriptive name — the function name is what `pg_prove` reports on failure.
- The whole file is wrapped in `BEGIN … ROLLBACK`, so both the seeded rows and the `test__*` functions themselves are discarded.

## Verify

Run the DB test suite. Two equivalent environments:

```bash
# Containerized (Postgres 17 + pgtap, matching CI — no native install needed):
make db-up       # HEART_DB_PORT=5433 make db-up if a native Postgres holds 5432
make test-db     # applies unapplied migrations, then runs the whole pgtap suite
                 # (needs PGUSER=postgres PGPASSWORD=postgres, plus PGPORT if remapped)

# Native Postgres with pgtap built locally:
make test-db     # PGHOST defaults to localhost; PGUSER/PGPASSWORD from your env
```

`make test-db` pins `PGHOST=localhost` deliberately — a bare `apply_migrations.sh`
without `PGHOST` falls back to fetching Supabase credentials from S3 and pointing at the
**shared** database. Never run the suite against Supabase. (`scripts/db_tests.sh` also
accepts the IDE run-config vars `DB_HOST_URL`/`DB_HOST_PORT`/`DB_USER`/`DB_PASSWORD`.)

### Reset — proving it applies from scratch

Running the file with `psql -f` proves the SQL parses; it does not prove the migration
*applies*, because the runner may skip it (see the naming section). And idempotent
re-runs only prove the migration works against the *current* state — a from-zero replay
is what proves the whole chain still works in order.

**Container (the cheap default, ~30s):**

```bash
make db-reset    # drops the data volume, rebuilds, waits healthy
make test-db     # expect ">> Migrations: N applied" replaying every file, then PASS
```

**Native Postgres** (no volume to drop) — surgical reset of just your migration:

```bash
psql -d heart --set ON_ERROR_STOP=1 -c "
  DELETE FROM _schema_migrations WHERE filename = '<file>.sql';
  DROP FUNCTION IF EXISTS <fn>(<argtypes>);
  ALTER TABLE <table> DROP COLUMN IF EXISTS <col>;   -- or DROP TABLE for a new table
"
PGHOST=localhost PGDATABASE=heart ./scripts/apply_migrations.sh   # expect ">> Applying <file>.sql"
```

Either way, confirm the objects exist — don't infer it from the runner's exit code:

```bash
psql -d heart -tAc "SELECT column_name FROM information_schema.columns WHERE table_name='<t>' AND column_name='<c>'"
psql -d heart -tAc "SELECT proname FROM pg_proc WHERE proname = '<fn>'"
psql -d heart -tAc "SELECT indexname FROM pg_indexes WHERE indexname = '<idx>'"
```

A reset discards data (the container's whole dataset; on native, whatever the dropped
column/table held). Repopulating is deterministic: `make db-seed` applies migrations and
syncs the exercise library from `content/` into the local database — no AWS involved,
idempotent, same source of truth the prod sync uses.

## If the table is read/written by the API

A new table usually means new API surface — see the `add-endpoint` skill. Remember the snake_case (row) ↔ camelCase (JSON) split when writing the model's `fromRow`/`toMap`.