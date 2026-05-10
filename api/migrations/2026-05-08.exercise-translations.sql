DROP TABLE IF EXISTS exercise_translations;
CREATE TABLE IF NOT EXISTS exercise_translations
(
    exercise_id  UUID NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    locale       TEXT NOT NULL,
    name         TEXT NOT NULL,
    instructions TEXT,
    PRIMARY KEY (exercise_id, locale)
);

CREATE UNIQUE INDEX IF NOT EXISTS exercises_user_name_idx
    ON exercises (user_id, name)
    WHERE user_id IS NOT NULL;