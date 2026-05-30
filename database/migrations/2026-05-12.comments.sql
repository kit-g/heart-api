DROP TABLE IF EXISTS comments;
CREATE TABLE IF NOT EXISTS comments
(
    id                  UUID        NOT NULL PRIMARY KEY DEFAULT uuidv7(),
    author_id           TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    body                TEXT        NOT NULL,
    workout_id          UUID REFERENCES workouts ON DELETE CASCADE,
    workout_exercise_id UUID REFERENCES workout_exercises ON DELETE CASCADE,
    exercise_set_id     UUID REFERENCES exercise_sets ON DELETE CASCADE,
    workout_image_id    UUID REFERENCES workout_images ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL             DEFAULT now(),
    edited_at           TIMESTAMPTZ,
    CONSTRAINT comments_body_nonempty
        CHECK (length(body) > 0),
    CONSTRAINT comments_exactly_one_target
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

CREATE INDEX IF NOT EXISTS comments_workout_idx ON comments (workout_id, created_at DESC) WHERE workout_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS comments_workout_exercise_idx ON comments (workout_exercise_id, created_at DESC) WHERE workout_exercise_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS comments_exercise_set_idx ON comments (exercise_set_id, created_at DESC) WHERE exercise_set_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS comments_workout_image_idx ON comments (workout_image_id, created_at DESC) WHERE workout_image_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS comments_author_idx ON comments (author_id, created_at DESC);

COMMENT ON TABLE comments IS 'Comments left by connected users on workouts, exercises, sets, or images';
COMMENT ON COLUMN comments.author_id IS 'User who wrote the comment';
COMMENT ON COLUMN comments.body IS 'Comment text';
COMMENT ON COLUMN comments.workout_id IS 'Target workout (mutually exclusive with other target FKs)';
COMMENT ON COLUMN comments.workout_exercise_id IS 'Target workout exercise (mutually exclusive)';
COMMENT ON COLUMN comments.exercise_set_id IS 'Target set (mutually exclusive)';
COMMENT ON COLUMN comments.workout_image_id IS 'Target gallery image (mutually exclusive)';
COMMENT ON COLUMN comments.edited_at IS 'Last edit timestamp, NULL if never edited';
COMMENT ON CONSTRAINT comments_exactly_one_target ON comments IS 'Comment must target exactly one of: workout, workout_exercise, exercise_set, workout_image';