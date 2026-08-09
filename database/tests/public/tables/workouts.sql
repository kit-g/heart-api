BEGIN;

SELECT plan(24);

SELECT has_table('public'::name, 'workouts'::name);

SELECT columns_are(
               'public',
               'workouts',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'started_at',
                   'completed_at',
                   'calories',
                   'created_at',
                   'import_id'
                   ]
       );

SELECT col_type_is('public'::name, 'workouts'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'started_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'completed_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'calories'::name, 'real'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'import_id'::name, 'text'::name);

SELECT has_pk('public'::name, 'workouts'::name, 'workouts has a primary key');
SELECT col_is_pk('public'::name, 'workouts'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'workouts'::name, 'id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'created_at'::name);

SELECT col_default_is('public', 'workouts', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'workouts', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'workouts', 'user_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'workouts'::name, 'workouts_user_id_idx'::name);
SELECT has_index('public'::name, 'workouts'::name, 'workouts_user_import_id_idx'::name);
SELECT index_is_unique('public'::name, 'workouts'::name, 'workouts_user_import_id_idx'::name);

-- fixture for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_profile('w-check-user');
END
$$;

SELECT lives_ok(
               $$ INSERT INTO workouts (user_id, calories) VALUES ('w-check-user', 0) $$,
               'zero calories are allowed'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, calories) VALUES ('w-check-user', -120) $$,
               '23514',
               NULL,
               'negative calories are rejected'
       );

-- first import row for the duplicate-identity assertion below
DO
$$
BEGIN
    INSERT INTO workouts (user_id, import_id) VALUES ('w-check-user', 'strong:2023-01-15 17:35:12#Push');
END
$$;

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, import_id) VALUES ('w-check-user', 'strong:2023-01-15 17:35:12#Push') $$,
               '23505',
               NULL,
               'the same import identity cannot land twice for one user'
       );

SELECT *
FROM finish();

ROLLBACK;
