BEGIN;

SELECT plan(16);

SELECT has_table('public'::name, 'given_names'::name);

SELECT columns_are(
               'public',
               'given_names',
               ARRAY [
                   'giver_id',
                   'person_id',
                   'name',
                   'updated_at'
                   ]
       );

SELECT has_pk('public'::name, 'given_names'::name);
SELECT col_is_pk('public'::name, 'given_names'::name, ARRAY ['giver_id', 'person_id']::name[]);

SELECT col_type_is('public'::name, 'given_names'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'given_names'::name, 'updated_at'::name, 'timestamp with time zone'::name);

SELECT col_not_null('public'::name, 'given_names'::name, 'giver_id'::name);
SELECT col_not_null('public'::name, 'given_names'::name, 'person_id'::name);
SELECT col_not_null('public'::name, 'given_names'::name, 'name'::name);
SELECT col_not_null('public'::name, 'given_names'::name, 'updated_at'::name);

SELECT fk_ok('public', 'given_names', 'giver_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'given_names', 'person_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'given_names'::name, 'given_names_person_idx'::name);

DO
$$
BEGIN
    PERFORM create_test_profile('given-a');
    PERFORM create_test_profile('given-b');
END
$$;

SELECT throws_ok(
               $$
               INSERT INTO given_names (giver_id, person_id, name) VALUES ('given-a', 'given-a', 'Me')
               $$,
               '23514',
               NULL,
               'nobody names themselves'
       );

SELECT throws_ok(
               $$
               INSERT INTO given_names (giver_id, person_id, name) VALUES ('given-a', 'given-b', '   ')
               $$,
               '23514',
               NULL,
               'a name has a word in it'
       );

SELECT throws_ok(
               $$
               INSERT INTO given_names (giver_id, person_id, name) VALUES ('given-a', 'given-b', repeat('x', 101))
               $$,
               '23514',
               NULL,
               'at most 100 characters'
       );

SELECT * FROM finish();

ROLLBACK;
