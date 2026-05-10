BEGIN;

SELECT plan(16);

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
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'workouts'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'started_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'completed_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'workouts'::name, 'workouts has a primary key');
SELECT col_is_pk('public'::name, 'workouts'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'workouts'::name, 'id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'created_at'::name);

SELECT col_default_is('public', 'workouts', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'workouts', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'workouts', 'user_id', 'public', 'profiles', 'id');

SELECT *
FROM finish();

ROLLBACK;
