BEGIN;

SELECT plan(41);

SELECT has_table('public'::name, 'goals'::name);

SELECT columns_are(
               'public',
               'goals',
               ARRAY [
                   'id',
                   'user_id',
                   'metric',
                   'exercise_id',
                   'cadence',
                   'stages',
                   'archived',
                   'created_at',
                   'pattern',
                   'muscle'
                   ]
       );

SELECT col_type_is('public'::name, 'goals'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'metric'::name, 'text'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'cadence'::name, 'text'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'stages'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'archived'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'pattern'::name, 'text'::name);
SELECT col_type_is('public'::name, 'goals'::name, 'muscle'::name, 'text'::name);

SELECT has_pk('public'::name, 'goals'::name, 'goals has a primary key');
SELECT col_is_pk('public'::name, 'goals'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'goals'::name, 'id'::name);
SELECT col_not_null('public'::name, 'goals'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'goals'::name, 'metric'::name);
SELECT col_not_null('public'::name, 'goals'::name, 'stages'::name);
SELECT col_not_null('public'::name, 'goals'::name, 'archived'::name);
SELECT col_not_null('public'::name, 'goals'::name, 'created_at'::name);

SELECT col_default_is('public', 'goals', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'goals', 'archived', 'false', 'archived defaults to false');
SELECT col_default_is('public', 'goals', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'goals', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'goals', 'exercise_id', 'public', 'exercises', 'id');

-- fixtures for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_profile('goal-test-user');
    PERFORM create_test_exercise('Goal Test Bench', _user_id := 'goal-test-user');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages)
               VALUES ('goal-test-user', 'workouts', 'week', '[{"id": "s1", "target": 3}]'::jsonb)
               $$,
               'a frequency goal has no exercise and a single standing target'
       );

SELECT lives_ok(
               $$
               INSERT INTO goals (user_id, metric, exercise_id, stages)
               VALUES (
                   'goal-test-user',
                   'topSetWeight',
                   (SELECT id FROM exercises WHERE name = 'Goal Test Bench'),
                   '[{"id": "s1", "target": 100, "dueOn": "2026-12-25"},
                     {"id": "s2", "target": 140, "dueOn": "2027-12-25"}]'::jsonb
               )
               $$,
               'a milestone ladder carries multiple staged targets'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, exercise_id, stages)
               VALUES (
                   'goal-test-user',
                   'workouts',
                   (SELECT id FROM exercises WHERE name = 'Goal Test Bench'),
                   '[{"id": "s1", "target": 3}]'::jsonb
               )
               $$,
               '23514',
               NULL,
               'the frequency metric rejects an exercise scope'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, stages)
               VALUES ('goal-test-user', 'topSetWeight', '[{"id": "s1", "target": 100}]'::jsonb)
               $$,
               '23514',
               NULL,
               'a per-exercise metric requires an exercise'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages)
               VALUES (
                   'goal-test-user',
                   'workouts',
                   'week',
                   '[{"id": "s1", "target": 3}, {"id": "s2", "target": 4}]'::jsonb
               )
               $$,
               '23514',
               NULL,
               'a recurring goal rejects a ladder'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages)
               VALUES ('goal-test-user', 'workouts', 'week', '[]'::jsonb)
               $$,
               '23514',
               NULL,
               'stages cannot be empty'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages)
               VALUES ('goal-test-user', 'bodyWeight', 'week', '[{"id": "s1", "target": 80}]'::jsonb)
               $$,
               '23514',
               NULL,
               'an unknown metric is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages)
               VALUES ('goal-test-user', 'workouts', 'fortnight', '[{"id": "s1", "target": 3}]'::jsonb)
               $$,
               '23514',
               NULL,
               'an unknown cadence is rejected'
       );

SELECT lives_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sessions', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, 'horizontal_press', NULL)
               $$,
               'a sessions goal can be about a pattern'
       );

SELECT lives_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sets', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, NULL, 'latissimus_dorsi')
               $$,
               'a sets goal can be about a muscle'
       );

SELECT lives_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sets', 'week', '[{"id": "s1", "target": 2}]'::jsonb, (SELECT id FROM exercises WHERE name = 'Goal Test Bench'), NULL, NULL)
               $$,
               'a sets goal can be about an exercise'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sessions', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, NULL, NULL)
               $$,
               '23514',
               NULL,
               'a sessions goal names a subject'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sets', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, 'horizontal_press', 'chest')
               $$,
               '23514',
               NULL,
               'a sets goal names one subject, not two'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'workouts', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, 'horizontal_press', NULL)
               $$,
               '23514',
               NULL,
               'the frequency metric takes no pattern'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'topSetWeight', NULL, '[{"id": "s1", "target": 100}]'::jsonb, (SELECT id FROM exercises WHERE name = 'Goal Test Bench'), 'horizontal_press', NULL)
               $$,
               '23514',
               NULL,
               'a per-exercise metric takes no pattern'
       );

SELECT throws_ok(
               $$
               INSERT INTO goals (user_id, metric, cadence, stages, exercise_id, pattern, muscle) VALUES ('goal-test-user', 'sessions', 'week', '[{"id": "s1", "target": 2}]'::jsonb, NULL, 'Horizontal Press', NULL)
               $$,
               '23514',
               NULL,
               'a pattern key is snake_case'
       );

SELECT * FROM finish();

ROLLBACK;
