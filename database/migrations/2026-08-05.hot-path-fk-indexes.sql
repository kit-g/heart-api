-- The workout/template child tables have carried no FK indexes since the initial
-- schema, so every `_workout_exercises` / `_exercise_sets` / `_template_exercises`
-- / `_template_exercise_sets` call and every cascade delete is a sequential scan.
-- 2026-08-01 fixed exactly this for templates (templates_user_order_idx); this
-- migration covers the remaining hot paths.

CREATE INDEX IF NOT EXISTS workout_exercises_workout_id_idx ON workout_exercises (workout_id);
CREATE INDEX IF NOT EXISTS exercise_sets_workout_exercise_id_idx ON exercise_sets (workout_exercise_id);
CREATE INDEX IF NOT EXISTS template_exercises_template_id_idx ON template_exercises (template_id);
CREATE INDEX IF NOT EXISTS template_exercise_sets_template_exercise_id_idx ON template_exercise_sets (template_exercise_id);

-- _listWorkouts filters on user_id and pages on (id < cursor) ORDER BY id DESC;
-- the composite makes the keyset scan a pure range scan, same shape as
-- templates_user_order_idx.
CREATE INDEX IF NOT EXISTS workouts_user_id_idx ON workouts (user_id, id);

COMMENT ON INDEX workout_exercises_workout_id_idx IS 'FK lookup for _workout_exercises and cascade deletes from workouts';
COMMENT ON INDEX exercise_sets_workout_exercise_id_idx IS 'FK lookup for _exercise_sets and cascade deletes from workout_exercises';
COMMENT ON INDEX template_exercises_template_id_idx IS 'FK lookup for _template_exercises and cascade deletes from templates';
COMMENT ON INDEX template_exercise_sets_template_exercise_id_idx IS 'FK lookup for _template_exercise_sets and cascade deletes from template_exercises';
COMMENT ON INDEX workouts_user_id_idx IS 'Keyset support for _listWorkouts: user_id scope, ORDER BY id DESC paging';
