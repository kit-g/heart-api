BEGIN;

SELECT plan(16);

SELECT has_schema('archive'::name);
SELECT has_table('archive'::name, 'deleted_workouts'::name);

SELECT columns_are(
               'archive',
               'deleted_workouts',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'started_at',
                   'completed_at',
                   'created_at',
                   'exercises',
                   'deleted_at'
                   ]
       );

SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'name'::name, 'text'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'started_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'completed_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'exercises'::name, 'jsonb'::name);
SELECT col_type_is('archive'::name, 'deleted_workouts'::name, 'deleted_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('archive'::name, 'deleted_workouts'::name, 'deleted_workouts has a primary key');
SELECT col_is_pk('archive'::name, 'deleted_workouts'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('archive'::name, 'deleted_workouts'::name, 'user_id'::name);
SELECT col_not_null('archive'::name, 'deleted_workouts'::name, 'deleted_at'::name);

SELECT col_default_is('archive', 'deleted_workouts', 'deleted_at', 'now()', 'deleted_at default is now()');

SELECT * FROM finish();

ROLLBACK;
