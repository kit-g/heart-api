-- Goals: a thing the user measures (workouts per week, a lift's top-set weight, monthly volume)
-- plus a ladder of stages — targets with their own deadlines ("two plates by Christmas, three by
-- next Christmas"). Definitions live here; progress is computed on-device from the local SQLite
-- mirror, so there is deliberately no aggregation in this schema.

DROP TABLE IF EXISTS goals CASCADE;

CREATE TABLE IF NOT EXISTS goals
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    metric      TEXT        NOT NULL,
    exercise_id UUID REFERENCES exercises (id) ON DELETE CASCADE,
    cadence     TEXT,
    stages      JSONB       NOT NULL,
    archived    BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT goals_metric_check CHECK (metric IN (
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
                                                    'totalTimeUnderTension'
        )),
    CONSTRAINT goals_cadence_check CHECK (cadence IS NULL OR cadence IN ('week', 'month')),
    CONSTRAINT goals_scope_check CHECK ((metric = 'workouts') = (exercise_id IS NULL)),
    CONSTRAINT goals_stages_check CHECK (jsonb_typeof(stages) = 'array' AND jsonb_array_length(stages) > 0),
    CONSTRAINT goals_cadence_stages_check CHECK (cadence IS NULL OR jsonb_array_length(stages) = 1)
);

CREATE INDEX IF NOT EXISTS goals_user_id_idx ON goals (user_id) WHERE NOT archived;
CREATE INDEX IF NOT EXISTS goals_exercise_id_idx ON goals (exercise_id) WHERE exercise_id IS NOT NULL;

COMMENT ON TABLE goals IS 'User goals: a measured metric plus a ladder of staged targets';
COMMENT ON COLUMN goals.metric IS
    'What is measured. Mirrors the app chart metrics (heart_db metrics.dart), plus "workouts" for frequency goals';
COMMENT ON COLUMN goals.exercise_id IS
    'Exercise the goal is about; NULL exactly when metric is "workouts" (whole-workout scope)';
COMMENT ON COLUMN goals.cadence IS
    'Recurring goal period ("week"/"month"); NULL means a one-off milestone ladder';
COMMENT ON COLUMN goals.stages IS
    'Ordered ladder of {id, target, dueOn, achievedAt}; array order is ladder order. Targets are metric (kg/km)';
COMMENT ON COLUMN goals.archived IS 'Soft-hides the goal without losing its achievement history';

COMMENT ON CONSTRAINT goals_scope_check ON goals IS
    'The frequency metric is whole-workout scoped; every other metric is per-exercise';
COMMENT ON CONSTRAINT goals_cadence_stages_check ON goals IS
    'A recurring goal has a single standing target; ladders are for milestones';
