BEGIN;

SELECT plan(12);

SELECT has_table('public'::name, 'import_names'::name);

SELECT columns_are('public', 'import_names', ARRAY ['source', 'title', 'name']);

SELECT col_type_is('public'::name, 'import_names'::name, 'source'::name, 'text'::name);
SELECT col_type_is('public'::name, 'import_names'::name, 'title'::name, 'text'::name);
SELECT col_type_is('public'::name, 'import_names'::name, 'name'::name, 'text'::name);

SELECT col_not_null('public'::name, 'import_names'::name, 'source'::name);
SELECT col_not_null('public'::name, 'import_names'::name, 'title'::name);
SELECT col_not_null('public'::name, 'import_names'::name, 'name'::name);

SELECT has_index('public'::name, 'import_names'::name, 'import_names_source_title_idx'::name);

SELECT lives_ok(
    $$INSERT INTO import_names (source, title, name) VALUES ('hevy', 'Bankdrücken (Langhantel)', 'Bench Press (Barbell)')$$,
    'a translated title resolves to an English one'
);
SELECT throws_ok(
    $$INSERT INTO import_names (source, title, name) VALUES ('hevy', 'bankdrücken (langhantel)', 'Bench Press (Barbell)')$$,
    '23505',
    NULL,
    'one resolution per title per app, case-insensitively'
);
SELECT throws_ok(
    $$INSERT INTO import_names (source, title, name) VALUES ('fitnotes', 'Bench', 'Bench Press (Barbell)')$$,
    '23514',
    NULL,
    'only the apps the import reads'
);

SELECT * FROM finish();

ROLLBACK;
