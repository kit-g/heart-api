DROP TABLE IF EXISTS workout_images;
CREATE TABLE IF NOT EXISTS workout_images
(
    id         UUID PRIMARY KEY DEFAULT uuidv7(),
    workout_id UUID NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL,
    key        TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ      DEFAULT now()
);
CREATE INDEX ON workout_images (user_id, id DESC);
CREATE INDEX ON workout_images (workout_id, key);