BEGIN;

SELECT plan(13);

SELECT has_table('public'::name, 'client_summaries'::name);

SELECT col_is_pk('public'::name, 'client_summaries'::name, 'connection_id'::name);

SELECT fk_ok('public', 'client_summaries', 'connection_id', 'public', 'connections', 'id');
SELECT fk_ok('public', 'client_summaries', 'coach_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'client_summaries', 'student_id', 'public', 'profiles', 'id');

SELECT col_default_is('public', 'client_summaries', 'dirty', 'true', 'worked out when first read');
SELECT col_default_is('public', 'client_summaries', 'generation', '0', 'from nothing');

SELECT has_index('public'::name, 'client_summaries'::name, 'client_summaries_coach_idx'::name);
SELECT has_index('public'::name, 'client_summaries'::name, 'client_summaries_student_idx'::name);

SELECT col_type_is('public'::name, 'client_summaries'::name, 'ending_since'::name, 'timestamp with time zone'::name);

SELECT has_trigger('public'::name, 'workouts'::name, 'workouts_mark_summaries_insert'::name);
SELECT has_trigger('public'::name, 'workouts'::name, 'workouts_mark_summaries_update'::name);
SELECT has_trigger('public'::name, 'workouts'::name, 'workouts_mark_summaries_delete'::name);

SELECT * FROM finish();

ROLLBACK;
