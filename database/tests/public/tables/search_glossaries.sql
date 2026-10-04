BEGIN;

SELECT plan(10);

SELECT has_table('public'::name, 'search_glossaries'::name);

SELECT columns_are('public', 'search_glossaries', ARRAY ['locale', 'terms']);

SELECT col_type_is('public'::name, 'search_glossaries'::name, 'locale'::name, 'text'::name);
SELECT col_type_is('public'::name, 'search_glossaries'::name, 'terms'::name, 'jsonb'::name);

SELECT col_is_pk('public'::name, 'search_glossaries'::name, 'locale'::name, 'locale is the primary key');
SELECT col_not_null('public'::name, 'search_glossaries'::name, 'terms'::name);
SELECT col_default_is('public', 'search_glossaries', 'terms', '{}'::jsonb, 'terms default is an empty map');

SELECT lives_ok(
    $$INSERT INTO search_glossaries (locale, terms) VALUES ('xx', '{"db": {"words": ["dumbbell"]}}')$$,
    'a map of terms is accepted'
);
SELECT throws_ok(
    $$INSERT INTO search_glossaries (locale, terms) VALUES ('yy', '["db"]')$$,
    '23514',
    NULL,
    'terms must be a map'
);
SELECT throws_ok(
    $$INSERT INTO search_glossaries (locale, terms) VALUES ('xx', '{}')$$,
    '23505',
    NULL,
    'one glossary per locale'
);

SELECT * FROM finish();

ROLLBACK;
