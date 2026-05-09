DROP TABLE IF EXISTS exercise_translations;
CREATE TABLE IF NOT EXISTS exercise_translations
(
    exercise_id  UUID NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    locale       TEXT NOT NULL,
    name         TEXT NOT NULL,
    instructions TEXT,
    PRIMARY KEY (exercise_id, locale)
);