BEGIN;

SELECT plan(34);

SELECT has_table('public'::name, 'programs'::name);

SELECT columns_are(
               'public',
               'programs',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'note',
                   'source',
                   'per_week',
                   'days',
                   'weeks',
                   'rules',
                   'constraint_key',
                   'archived',
                   'created_at',
                   'updated_at',
                   'deload'
                   ]
       );

SELECT col_type_is('public'::name, 'programs'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'note'::name, 'text'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'source'::name, 'text'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'per_week'::name, 'smallint'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'days'::name, 'smallint[]'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'weeks'::name, 'smallint'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'rules'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'constraint_key'::name, 'text'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'archived'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'updated_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'programs'::name, 'deload'::name, 'jsonb'::name);

SELECT has_pk('public'::name, 'programs'::name, 'programs has a primary key');
SELECT col_is_pk('public'::name, 'programs'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'programs'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'programs'::name, 'name'::name);
SELECT col_not_null('public'::name, 'programs'::name, 'days'::name);
SELECT col_not_null('public'::name, 'programs'::name, 'rules'::name);
SELECT col_not_null('public'::name, 'programs'::name, 'archived'::name);

SELECT col_default_is('public', 'programs', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'programs', 'days', '{}'::smallint[], 'days default is empty');
SELECT col_default_is('public', 'programs', 'rules', '{}'::jsonb, 'rules default is an empty object');
SELECT col_default_is('public', 'programs', 'archived', 'false', 'archived default is false');

SELECT fk_ok('public', 'programs', 'user_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'programs'::name, 'programs_user_id_idx'::name);

-- the shape checks
SELECT throws_ok(
               $$INSERT INTO programs (user_id, name, per_week) VALUES (create_test_profile(), 'p', 29)$$,
               '23514', NULL, 'per_week stops at 28'
       );
SELECT throws_ok(
               $$INSERT INTO programs (user_id, name, days) VALUES (create_test_profile(), 'p', '{0}')$$,
               '23514', NULL, 'days are ISO weekdays'
       );
SELECT throws_ok(
               $$INSERT INTO programs (user_id, name, rules) VALUES (create_test_profile(), 'p', '[]')$$,
               '23514', NULL, 'rules is an object'
       );
SELECT throws_ok(
               $$INSERT INTO programs (user_id, name) VALUES (create_test_profile(), '  ')$$,
               '23514', NULL, 'a name is never blank'
       );

SELECT throws_ok(
               $$INSERT INTO programs (user_id, name, deload) VALUES (create_test_profile(), 'p', '{"load": 0.9}')$$,
               '23514', NULL, 'a deload says how often'
       );

SELECT * FROM finish();

ROLLBACK;
