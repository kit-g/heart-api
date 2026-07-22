---
name: add-migration
description: Add a database migration and its pgtap test to database/. Use whenever creating or altering a table/function/index. Encodes the file-naming, house SQL style, snake_case rule, and the pgtap plan(N) gotchas. Triggers: "add a migration", "new table", "alter table", "add a column", "new DB function".
---

# Adding a migration + pgtap test

The migration runner applies `database/migrations/*.sql` in filename sort order, tracked in `_schema_migrations`. Tests live in `database/tests/**/*.sql` and run under `pg_prove`.

## Naming

`database/migrations/YYYY-MM-DD.short-name.sql` — date-prefixed (sorts chronologically = apply order), kebab-case slug. Use today's date. If two migrations share a date, the slug breaks the tie alphabetically — name them so the intended order holds.

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

pgtap covers **schema and signatures** (tables, columns, types, PKs, FKs, function shapes) — it does **not** test query behavior. The SQL the API actually runs lives in `api/lib/db/queries.dart`; its behavior is covered by `db`-tagged Dart integration tests (see the `add-endpoint` skill), not here.

Add `database/tests/<schema>/tables/<table>.sql` (or `functions/` for functions). Structure:

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
SELECT * FROM finish();
ROLLBACK;
```

### plan(N) gotcha — the thing that bites

`plan(N)` must equal the **exact** count of `SELECT`-assertion calls. Count them after writing, don't estimate. `columns_are` is ONE assertion regardless of column count. Each `col_type_is`/`col_not_null`/`fk_ok` is one each. If `pg_prove` says "looks like you planned N but ran M", fix the number, don't add filler.

### Other gotchas

- `col_default_is` wants the **rendered** default exactly as Postgres stores it: `uuidv7()`, `now()`, `'en'` (text), `'{}'::jsonb`. When unsure, check an existing table's test or query `information_schema.columns`.
- `col_type_is` type names: `uuid`, `text`, `integer`, `boolean`, `jsonb`, `timestamp with time zone` (not `timestamptz`), `real`.

## Verify

Run the DB test suite (needs local Postgres + pgtap):

```bash
./scripts/apply_migrations.sh        # applies your new migration
psql -f database/test_utils/helpers.sql
cd database && pg_prove tests/**/*.sql   # zsh expands ** natively; CI uses bash -O globstar
```

Or the convenience wrapper if present: `./scripts/db_tests.sh`.

## If the table is read/written by the API

A new table usually means new API surface — see the `add-endpoint` skill. Remember the snake_case (row) ↔ camelCase (JSON) split when writing the model's `fromRow`/`toMap`.