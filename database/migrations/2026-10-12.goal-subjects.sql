-- Goals about a movement pattern or a muscle, not only an exercise:
--
--   goals.pattern  a movement pattern key from the exercise library (horizontal_press)
--   goals.muscle   a muscle id prefix (triceps_brachii) or a muscle group (chest)
--
-- Two metrics count what trained one subject: sessions (workouts that trained
-- it) and sets (working sets on it). Each names exactly one of exercise_id,
-- pattern and muscle. The other metrics keep their scope, and neither new
-- column is set on them.
--
-- Pattern and muscle keys are library content and can grow without a
-- migration, so the schema checks their spelling, not a list.
--
-- No DROP before the ADD: the columns hold what users wrote.

ALTER TABLE IF EXISTS goals
    ADD COLUMN IF NOT EXISTS pattern TEXT,
    ADD COLUMN IF NOT EXISTS muscle TEXT;

ALTER TABLE IF EXISTS goals
    DROP CONSTRAINT IF EXISTS goals_metric_check,
    ADD CONSTRAINT goals_metric_check CHECK (metric IN (
        'workouts',
        'topSetWeight',
        'estimatedOneRepMax',
        'totalVolume',
        'totalReps',
        'maxConsecutiveReps',
        'averageWorkingWeight',
        'assistanceWeight',
        'cardioDistance',
        'cardioDuration',
        'averagePace',
        'totalTimeUnderTension',
        'sessions',
        'sets'
    )),
    DROP CONSTRAINT IF EXISTS goals_scope_check,
    ADD CONSTRAINT goals_scope_check CHECK (
        CASE
            WHEN metric = 'workouts' THEN num_nonnulls(exercise_id, pattern, muscle) = 0
            WHEN metric IN ('sessions', 'sets') THEN num_nonnulls(exercise_id, pattern, muscle) = 1
            ELSE exercise_id IS NOT NULL AND num_nonnulls(pattern, muscle) = 0
        END
    ),
    DROP CONSTRAINT IF EXISTS goals_subject_key_check,
    ADD CONSTRAINT goals_subject_key_check CHECK (
        (pattern IS NULL OR pattern ~ '^[a-z][a-z0-9_]{0,63}$')
        AND (muscle IS NULL OR muscle ~ '^[a-z][a-z0-9_]{0,63}$')
    );

COMMENT ON COLUMN goals.metric IS
    'What is measured. Mirrors the app chart metrics (heart_db metrics.dart), plus "workouts" for frequency goals and "sessions"/"sets" for counts on one subject';
COMMENT ON COLUMN goals.exercise_id IS
    'Exercise the goal is about: required by the per-exercise metrics, one of three subjects for sessions and sets, NULL for workouts';
COMMENT ON COLUMN goals.pattern IS
    'Movement pattern key from the exercise library a sessions or sets goal is about; NULL otherwise';
COMMENT ON COLUMN goals.muscle IS
    'Muscle id prefix or muscle group a sessions or sets goal is about; NULL otherwise';
COMMENT ON CONSTRAINT goals_metric_check ON goals IS
    'The metric vocabulary; a new metric arrives here and in the client''s enum together';
COMMENT ON CONSTRAINT goals_scope_check ON goals IS
    'workouts names no subject; sessions and sets name exactly one of exercise, pattern and muscle; every other metric names an exercise';
COMMENT ON CONSTRAINT goals_subject_key_check ON goals IS
    'Pattern and muscle keys are snake_case content identifiers, at most 64 characters; the set of valid keys is the library''s';
