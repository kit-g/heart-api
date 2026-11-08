-- A person's reaction to something they can read: a workout, an exercise in it, a set, or a photo,
-- the same things a comment can be on. One per person per thing; changing it replaces the word.

DROP TABLE IF EXISTS reactions;
CREATE TABLE IF NOT EXISTS reactions
(
    id                  UUID        NOT NULL PRIMARY KEY DEFAULT uuidv7(),
    author_id           TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    kind                TEXT        NOT NULL,
    workout_id          UUID REFERENCES workouts ON DELETE CASCADE,
    workout_exercise_id UUID REFERENCES workout_exercises ON DELETE CASCADE,
    exercise_set_id     UUID REFERENCES exercise_sets ON DELETE CASCADE,
    workout_image_id    UUID REFERENCES workout_images ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL             DEFAULT now(),
    CONSTRAINT reactions_kind_check CHECK (kind ~ '^[a-z][a-z0-9_]{0,31}$'),
    CONSTRAINT reactions_exactly_one_target
        CHECK (
            (workout_id IS NOT NULL)::int
                +
            (workout_exercise_id IS NOT NULL)::int
                +
            (exercise_set_id IS NOT NULL)::int
                +
            (workout_image_id IS NOT NULL)::int = 1
            )
);

CREATE UNIQUE INDEX IF NOT EXISTS reactions_workout_key
    ON reactions (workout_id, author_id) WHERE workout_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reactions_workout_exercise_key
    ON reactions (workout_exercise_id, author_id) WHERE workout_exercise_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reactions_exercise_set_key
    ON reactions (exercise_set_id, author_id) WHERE exercise_set_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reactions_workout_image_key
    ON reactions (workout_image_id, author_id) WHERE workout_image_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS reactions_author_idx ON reactions (author_id);

COMMENT ON TABLE reactions IS 'Reactions people leave on workouts, exercises, sets or photos they can read';
COMMENT ON COLUMN reactions.author_id IS 'Who reacted';
COMMENT ON COLUMN reactions.kind IS 'The reaction, a word such as cheer; an open vocabulary';
COMMENT ON COLUMN reactions.workout_id IS 'Target workout (mutually exclusive with the other targets)';
COMMENT ON COLUMN reactions.workout_exercise_id IS 'Target workout exercise (mutually exclusive)';
COMMENT ON COLUMN reactions.exercise_set_id IS 'Target set (mutually exclusive)';
COMMENT ON COLUMN reactions.workout_image_id IS 'Target photo (mutually exclusive)';
COMMENT ON COLUMN reactions.created_at IS 'When the reaction was first left; a changed word keeps it';
COMMENT ON CONSTRAINT reactions_kind_check ON reactions IS 'A snake_case word of at most 32 characters';
COMMENT ON CONSTRAINT reactions_exactly_one_target ON reactions IS 'A reaction is on exactly one of: workout, workout_exercise, exercise_set, workout_image';
COMMENT ON INDEX reactions_workout_key IS 'One reaction per person on a workout, and the reactions on one';
COMMENT ON INDEX reactions_workout_exercise_key IS 'One reaction per person on an exercise, and the reactions on one';
COMMENT ON INDEX reactions_exercise_set_key IS 'One reaction per person on a set, and the reactions on one';
COMMENT ON INDEX reactions_workout_image_key IS 'One reaction per person on a photo, and the reactions on one';
COMMENT ON INDEX reactions_author_idx IS 'The cascade when a profile is deleted';
