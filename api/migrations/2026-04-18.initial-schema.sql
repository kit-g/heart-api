DROP TABLE IF EXISTS workout_images CASCADE;
DROP TABLE IF EXISTS workouts CASCADE;
DROP TABLE IF EXISTS template_exercise_sets CASCADE;
DROP TABLE IF EXISTS template_exercises CASCADE;
DROP TABLE IF EXISTS template_shares CASCADE;
DROP TABLE IF EXISTS templates CASCADE;
DROP TABLE IF EXISTS chart_preferences CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

CREATE TABLE IF NOT EXISTS profiles
(
    id                        TEXT PRIMARY KEY,
    username                  TEXT,
    email                     TEXT,
    avatar_url                TEXT,
    account_deletion_schedule TEXT,
    scheduled_for_deletion_at TIMESTAMPTZ,
    updated_at                TIMESTAMPTZ DEFAULT now()
);

DROP TABLE IF EXISTS exercises CASCADE;
CREATE TABLE IF NOT EXISTS exercises
(
    id           UUID             DEFAULT uuidv7() PRIMARY KEY,
    name         TEXT    NOT NULL,
    category     TEXT    NOT NULL,
    target       TEXT    NOT NULL,
    instructions TEXT,
    asset        JSONB,
    thumbnail    JSONB,
    archived     BOOLEAN NOT NULL DEFAULT false,
    muscles      JSONB,
    user_id      TEXT REFERENCES profiles (id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ      DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS exercises_global_name_idx ON exercises (name) WHERE user_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS exercises_user_name_idx ON exercises (user_id, name) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS exercises_user_id_idx ON exercises (user_id);

DROP TABLE IF EXISTS connections CASCADE;
CREATE TABLE IF NOT EXISTS connections
(
    initiator_id   TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    target_id      TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    initiator_role TEXT NOT NULL,
    target_role    TEXT NOT NULL,
    domain         TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'pending',
    created_at     TIMESTAMPTZ   DEFAULT now(),
    PRIMARY KEY (initiator_id, target_id, domain),
    check ( length(domain) > 0 ),
    check ( length(status) > 0 ),
    check ( length(initiator_role) > 0 ),
    check ( length(target_role) > 0 )
);
CREATE INDEX idx_connections_target_id ON connections (target_id);

CREATE TABLE IF NOT EXISTS workouts
(
    id           UUID        DEFAULT uuidv7() PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name         TEXT,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ DEFAULT now(),
    check ( length(name) >= 0 )
);

DROP TABLE IF EXISTS workout_exercises CASCADE;
CREATE TABLE IF NOT EXISTS workout_exercises
(
    id             UUID DEFAULT uuidv7() PRIMARY KEY,
    workout_id     UUID    NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    exercise_id    UUID    NOT NULL,
    exercise_order INTEGER NOT NULL,
    check ( exercise_order >= 0 )
);

DROP TABLE IF EXISTS exercise_sets CASCADE;
CREATE TABLE IF NOT EXISTS exercise_sets
(
    id                  UUID    DEFAULT uuidv7() PRIMARY KEY,
    workout_exercise_id UUID    NOT NULL REFERENCES workout_exercises (id) ON DELETE CASCADE,
    weight              REAL,
    reps                INTEGER,
    duration            INTEGER,
    distance            REAL,
    completed           BOOLEAN DEFAULT false,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    set_order           INTEGER NOT NULL,
    check ( set_order >= 0 )
);

CREATE TABLE IF NOT EXISTS workout_images
(
    id         UUID        DEFAULT uuidv7() PRIMARY KEY,
    workout_id UUID NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    image_key  TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    check ( length(image_key) > 0 )
);

CREATE TABLE IF NOT EXISTS templates
(
    id                 UUID             DEFAULT uuidv7() PRIMARY KEY,
    user_id            TEXT    NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name               TEXT,
    order_index        INTEGER NOT NULL DEFAULT 0,
    source_template_id UUID    REFERENCES templates (id) ON DELETE SET NULL,
    assigned_by        TEXT REFERENCES profiles (id),
    sync_enabled       BOOLEAN,
    created_at         TIMESTAMPTZ      DEFAULT now()
);

CREATE TABLE IF NOT EXISTS template_exercises
(
    id             UUID DEFAULT uuidv7() PRIMARY KEY,
    template_id    UUID    NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    exercise_id    TEXT    NOT NULL,
    exercise_order INTEGER NOT NULL,
    check ( exercise_order >= 0 )
);

CREATE TABLE IF NOT EXISTS template_exercise_sets
(
    id                   UUID DEFAULT uuidv7() PRIMARY KEY,
    template_exercise_id UUID    NOT NULL REFERENCES template_exercises (id) ON DELETE CASCADE,
    weight               REAL,
    reps                 INTEGER,
    duration             INTEGER,
    distance             REAL,
    set_order            INTEGER NOT NULL,
    check ( set_order >= 0 )
);

CREATE TABLE IF NOT EXISTS template_shares
(
    id                  UUID        DEFAULT uuidv7() PRIMARY KEY,
    coach_id            TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    student_id          TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    master_template_id  UUID NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    student_template_id UUID NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ DEFAULT now(),
    UNIQUE (coach_id, master_template_id, student_id)
);

CREATE TABLE IF NOT EXISTS chart_preferences
(
    id          UUID        DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL,
    chart_type  TEXT NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT now(),
    UNIQUE (user_id, exercise_id)
);

