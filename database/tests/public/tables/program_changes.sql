BEGIN;

SELECT plan(14);

SELECT has_table('public'::name, 'program_changes'::name);
SELECT columns_are(
               'public', 'program_changes',
               ARRAY ['id', 'program_id', 'session_id', 'actor_id', 'kind', 'revision', 'before', 'after', 'links', 'stale', 'at', 'xid']
       );
SELECT col_is_pk('public'::name, 'program_changes'::name, 'id'::name);
SELECT fk_ok('public', 'program_changes', 'program_id', 'public', 'programs', 'id');
SELECT fk_ok('public', 'program_changes', 'actor_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'program_changes'::name, 'program_changes_order_idx'::name);
SELECT has_index('public'::name, 'program_changes'::name, 'program_changes_subject_idx'::name);
SELECT has_column('public', 'programs', 'revision', 'a program has a revision');
SELECT col_default_is('public', 'programs', 'revision', '0', 'from nothing');
SELECT has_column('public', 'templates', 'revision', 'and so does a session');
SELECT col_default_is('public', 'templates', 'revision', '0', 'from nothing');

SELECT has_table('public'::name, 'workout_plans'::name);
SELECT col_is_pk('public'::name, 'workout_plans'::name, 'workout_id'::name);
SELECT fk_ok('public', 'workout_plans', 'workout_id', 'public', 'workouts', 'id');

SELECT * FROM finish();

ROLLBACK;
