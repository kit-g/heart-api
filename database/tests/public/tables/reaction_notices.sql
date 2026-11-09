BEGIN;

SELECT plan(12);

SELECT has_table('public'::name, 'reaction_notices'::name);

SELECT columns_are(
               'public',
               'reaction_notices',
               ARRAY [
                   'author_id',
                   'workout_id',
                   'told_at'
                   ]
       );

SELECT col_type_is('public'::name, 'reaction_notices'::name, 'author_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'reaction_notices'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reaction_notices'::name, 'told_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'reaction_notices'::name, ARRAY ['author_id', 'workout_id']);

SELECT col_not_null('public'::name, 'reaction_notices'::name, 'told_at'::name);
SELECT col_default_is('public', 'reaction_notices', 'told_at', 'now()', 'told_at defaults to now()');

SELECT fk_ok('public', 'reaction_notices', 'author_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'reaction_notices', 'workout_id', 'public', 'workouts', 'id');

SELECT has_index('public'::name, 'reaction_notices'::name, 'reaction_notices_workout_idx'::name);
SELECT has_pk('public'::name, 'reaction_notices'::name);

SELECT * FROM finish();

ROLLBACK;
