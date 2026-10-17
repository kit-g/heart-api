BEGIN;

SELECT plan(30);

SELECT has_table('public'::name, 'anomalies'::name);

SELECT columns_are(
               'public',
               'anomalies',
               ARRAY [
                   'id',
                   'user_id',
                   'workout_id',
                   'set_id',
                   'reason',
                   'observed',
                   'typical',
                   'status',
                   'detected_at',
                   'resolved_at'
                   ]
       );

SELECT col_type_is('public'::name, 'anomalies'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'set_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'reason'::name, 'text'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'observed'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'typical'::name, 'real'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'status'::name, 'text'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'detected_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'anomalies'::name, 'resolved_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'anomalies'::name, 'id'::name);

SELECT col_not_null('public'::name, 'anomalies'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'anomalies'::name, 'workout_id'::name);
SELECT col_not_null('public'::name, 'anomalies'::name, 'reason'::name);
SELECT col_not_null('public'::name, 'anomalies'::name, 'observed'::name);
SELECT col_not_null('public'::name, 'anomalies'::name, 'status'::name);
SELECT col_not_null('public'::name, 'anomalies'::name, 'detected_at'::name);

SELECT col_default_is('public', 'anomalies', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'anomalies', 'status', 'pending'::text, 'status defaults to pending');
SELECT col_default_is('public', 'anomalies', 'detected_at', 'now()', 'detected_at defaults to now()');

SELECT fk_ok('public', 'anomalies', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'anomalies', 'workout_id', 'public', 'workouts', 'id');
SELECT fk_ok('public', 'anomalies', 'set_id', 'public', 'exercise_sets', 'id');

SELECT index_is_unique('public'::name, 'anomalies'::name, 'anomalies_set_reason_idx'::name);
SELECT index_is_unique('public'::name, 'anomalies'::name, 'anomalies_workout_reason_idx'::name);
SELECT has_index('public'::name, 'anomalies'::name, 'anomalies_user_idx'::name, ARRAY ['user_id', 'id']::name[]);

SELECT throws_ok(
               $$INSERT INTO anomalies (user_id, workout_id, reason, observed, status)
                 VALUES (create_test_profile(), create_test_workout(), 'duration_left_running', '{}', 'invalid')$$,
               '23514',
               NULL,
               'a resolved anomaly carries when it was resolved'
       );

SELECT throws_ok(
               $$INSERT INTO anomalies (user_id, workout_id, reason, observed)
                 VALUES (create_test_profile(), create_test_workout(), 'outlier_weight', '{}')$$,
               '23514',
               NULL,
               'a set''s reason needs a set'
       );

SELECT * FROM finish();

ROLLBACK;
