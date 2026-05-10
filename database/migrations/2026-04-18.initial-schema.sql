DROP TABLE IF EXISTS exercise_sets CASCADE;
DROP TABLE IF EXISTS workout_exercises CASCADE;
DROP TABLE IF EXISTS workout_images CASCADE;
DROP TABLE IF EXISTS workouts CASCADE;
DROP TABLE IF EXISTS template_exercise_sets CASCADE;
DROP TABLE IF EXISTS template_exercises CASCADE;
DROP TABLE IF EXISTS template_shares CASCADE;
DROP TABLE IF EXISTS templates CASCADE;
DROP TABLE IF EXISTS chart_preferences CASCADE;
DROP TABLE IF EXISTS exercises CASCADE;
DROP TABLE IF EXISTS connections CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

CREATE TABLE IF NOT EXISTS profiles
(
    id                        TEXT PRIMARY KEY,
    username                  TEXT,
    email                     TEXT,
    avatar_url                TEXT,
    account_deletion_schedule TEXT,
    scheduled_for_deletion_at TIMESTAMPTZ,
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS exercises
(
    id           UUID                 DEFAULT uuidv7() PRIMARY KEY,
    name         TEXT        NOT NULL,
    category     TEXT        NOT NULL,
    target       TEXT        NOT NULL,
    instructions TEXT,
    asset        JSONB,
    thumbnail    JSONB,
    archived     BOOLEAN     NOT NULL DEFAULT false,
    muscles      JSONB,
    user_id      TEXT REFERENCES profiles (id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS exercises_global_name_idx ON exercises (name) WHERE user_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS exercises_user_name_idx ON exercises (user_id, name) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS exercises_user_id_idx ON exercises (user_id);

CREATE TABLE IF NOT EXISTS connections
(
    initiator_id   TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    target_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    initiator_role TEXT        NOT NULL,
    target_role    TEXT        NOT NULL,
    domain         TEXT        NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'pending',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (initiator_id, target_id, domain),
    CHECK (length(domain) > 0),
    CHECK (length(status) > 0),
    CHECK (length(initiator_role) > 0),
    CHECK (length(target_role) > 0)
);
CREATE INDEX idx_connections_target_id ON connections (target_id);

CREATE TABLE IF NOT EXISTS workouts
(
    id           UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name         TEXT,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT workouts_name_nonempty_check CHECK (name IS NULL OR length(name) > 0)
);

CREATE TABLE IF NOT EXISTS workout_exercises
(
    id             UUID DEFAULT uuidv7() PRIMARY KEY,
    workout_id     UUID    NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    exercise_id    UUID    NOT NULL REFERENCES exercises (id) ON DELETE RESTRICT,
    exercise_order INTEGER NOT NULL,
    CHECK (exercise_order >= 0)
);

CREATE TABLE IF NOT EXISTS exercise_sets
(
    id                  UUID             DEFAULT uuidv7() PRIMARY KEY,
    workout_exercise_id UUID    NOT NULL REFERENCES workout_exercises (id) ON DELETE CASCADE,
    weight              REAL,
    reps                INTEGER,
    duration            INTEGER,
    distance            REAL,
    completed           BOOLEAN NOT NULL DEFAULT false,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    set_order           INTEGER NOT NULL,
    CHECK (set_order >= 0)
);

CREATE TABLE IF NOT EXISTS workout_images
(
    id         UUID PRIMARY KEY     DEFAULT uuidv7(),
    workout_id UUID        NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    user_id    TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    key        TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (length(key) > 0)
);
CREATE INDEX ON workout_images (user_id, id DESC);
CREATE INDEX ON workout_images (workout_id, key);

CREATE TABLE IF NOT EXISTS templates
(
    id                 UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id            TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name               TEXT,
    order_index        INTEGER     NOT NULL DEFAULT 0,
    source_template_id UUID        REFERENCES templates (id) ON DELETE SET NULL,
    assigned_by        TEXT        REFERENCES profiles (id) ON DELETE SET NULL,
    sync_enabled       BOOLEAN,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS template_exercises
(
    id             UUID DEFAULT uuidv7() PRIMARY KEY,
    template_id    UUID    NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    exercise_id    UUID    NOT NULL REFERENCES exercises (id) ON DELETE RESTRICT,
    exercise_order INTEGER NOT NULL,
    CHECK (exercise_order >= 0)
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
    CHECK (set_order >= 0)
);

CREATE TABLE IF NOT EXISTS template_shares
(
    id                  UUID                 DEFAULT uuidv7() PRIMARY KEY,
    coach_id            TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    student_id          TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    master_template_id  UUID        NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    student_template_id UUID        NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (coach_id, master_template_id, student_id)
);

CREATE TABLE IF NOT EXISTS chart_preferences
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    exercise_id TEXT        NOT NULL,
    chart_type  TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, exercise_id)
);

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

-- tables
COMMENT ON TABLE profiles IS 'User profiles';
COMMENT ON TABLE exercises IS 'Exercise definitions including both global and user-created exercises';
COMMENT ON TABLE connections IS 'Relationships between users (e.g., coach-student connections)';
COMMENT ON TABLE workouts IS 'User workout sessions with start and completion timestamps';
COMMENT ON TABLE workout_exercises IS 'Exercises performed in a workout with their order';
COMMENT ON TABLE exercise_sets IS 'Individual sets performed for each exercise in a workout';
COMMENT ON TABLE workout_images IS 'Images associated with workout sessions';
COMMENT ON TABLE templates IS 'Workout templates that can be shared between users';
COMMENT ON TABLE template_exercises IS 'Exercises included in a template with their order';
COMMENT ON TABLE template_exercise_sets IS 'Predefined sets for exercises in a template';
COMMENT ON TABLE template_shares IS 'Template sharing relationships between coaches and students';
COMMENT ON TABLE chart_preferences IS 'User preferences for exercise chart visualization';
COMMENT ON TABLE exercise_translations IS 'Localized translations for exercise names and instructions';

-- profiles
COMMENT ON COLUMN profiles.username IS 'User display name';
COMMENT ON COLUMN profiles.email IS 'User email address';
COMMENT ON COLUMN profiles.avatar_url IS 'URL to user avatar image';
COMMENT ON COLUMN profiles.account_deletion_schedule IS 'AWS Scheduler ARN for the account deletion schedule ';
COMMENT ON COLUMN profiles.scheduled_for_deletion_at IS 'Timestamp when account deletion is scheduled';
COMMENT ON COLUMN profiles.updated_at IS 'Last profile update timestamp';

--  exercises
COMMENT ON COLUMN exercises.name IS 'Exercise name';
COMMENT ON COLUMN exercises.category IS 'Exercise category (e.g., strength, cardio)';
COMMENT ON COLUMN exercises.target IS 'Primary muscle or body area targeted';
COMMENT ON COLUMN exercises.instructions IS 'Exercise instructions or description';
COMMENT ON COLUMN exercises.asset IS 'Media assets (images, videos) in JSON format';
COMMENT ON COLUMN exercises.thumbnail IS 'Thumbnail image data in JSON format';
COMMENT ON COLUMN exercises.archived IS 'Whether the exercise is archived';
COMMENT ON COLUMN exercises.muscles IS 'Detailed muscle groups targeted in JSON format';
COMMENT ON COLUMN exercises.user_id IS 'User who created the exercise (NULL for global exercises)';
COMMENT ON COLUMN exercises.created_at IS 'Exercise creation timestamp';

-- connections
COMMENT ON COLUMN connections.initiator_id IS 'User who initiated the connection';
COMMENT ON COLUMN connections.target_id IS 'User who received the connection request';
COMMENT ON COLUMN connections.initiator_role IS 'Role of the initiator in this connection';
COMMENT ON COLUMN connections.target_role IS 'Role of the target in this connection';
COMMENT ON COLUMN connections.domain IS 'Reason the connection is initiated, e.g., fitness';
COMMENT ON COLUMN connections.status IS 'Connection status';
COMMENT ON COLUMN connections.created_at IS 'Connection request creation timestamp';

-- workouts
COMMENT ON COLUMN workouts.user_id IS 'User who performed the workout';
COMMENT ON COLUMN workouts.name IS 'Workout name or title';
COMMENT ON COLUMN workouts.started_at IS 'Workout start timestamp';
COMMENT ON COLUMN workouts.completed_at IS 'Workout completion timestamp';
COMMENT ON COLUMN workouts.created_at IS 'Workout record creation timestamp';

-- workout_exercises
COMMENT ON COLUMN workout_exercises.workout_id IS 'Associated workout';
COMMENT ON COLUMN workout_exercises.exercise_id IS 'Exercise performed';
COMMENT ON COLUMN workout_exercises.exercise_order IS 'Order of exercise in the workout';

-- exercise_sets
COMMENT ON COLUMN exercise_sets.workout_exercise_id IS 'Associated workout exercise';
COMMENT ON COLUMN exercise_sets.weight IS 'Weight used in the set (kg or lbs)';
COMMENT ON COLUMN exercise_sets.reps IS 'Number of repetitions performed';
COMMENT ON COLUMN exercise_sets.duration IS 'Duration of the set in seconds';
COMMENT ON COLUMN exercise_sets.distance IS 'Distance covered (for cardio exercises)';
COMMENT ON COLUMN exercise_sets.completed IS 'Whether the set was completed';
COMMENT ON COLUMN exercise_sets.started_at IS 'Set start timestamp';
COMMENT ON COLUMN exercise_sets.completed_at IS 'Set completion timestamp';
COMMENT ON COLUMN exercise_sets.set_order IS 'Order of set within the exercise';

-- workout_images
COMMENT ON COLUMN workout_images.workout_id IS 'Associated workout';
COMMENT ON COLUMN workout_images.user_id IS 'User who uploaded the image';
COMMENT ON COLUMN workout_images.key IS 'Storage key or path for the image';
COMMENT ON COLUMN workout_images.created_at IS 'Image upload timestamp';

-- templates
COMMENT ON COLUMN templates.user_id IS 'User who owns the template';
COMMENT ON COLUMN templates.name IS 'Template name';
COMMENT ON COLUMN templates.order_index IS 'Display order for user templates';
COMMENT ON COLUMN templates.source_template_id IS 'Original template if this is a copy';
COMMENT ON COLUMN templates.assigned_by IS 'User who assigned this template (for shared templates)';
COMMENT ON COLUMN templates.sync_enabled IS 'Whether changes to source template sync to this copy';
COMMENT ON COLUMN templates.created_at IS 'Template creation timestamp';

-- template_exercises
COMMENT ON COLUMN template_exercises.id IS 'Unique template exercise identifier';
COMMENT ON COLUMN template_exercises.template_id IS 'Associated template';
COMMENT ON COLUMN template_exercises.exercise_id IS 'Exercise included in template';
COMMENT ON COLUMN template_exercises.exercise_order IS 'Order of exercise in the template';

-- template_exercise_sets
COMMENT ON COLUMN template_exercise_sets.template_exercise_id IS 'Associated template exercise';
COMMENT ON COLUMN template_exercise_sets.weight IS 'Target weight for the set';
COMMENT ON COLUMN template_exercise_sets.reps IS 'Target number of repetitions';
COMMENT ON COLUMN template_exercise_sets.duration IS 'Target duration in seconds';
COMMENT ON COLUMN template_exercise_sets.distance IS 'Target distance';
COMMENT ON COLUMN template_exercise_sets.set_order IS 'Order of set within the template exercise';

-- template_shares
COMMENT ON COLUMN template_shares.id IS 'Unique share identifier';
COMMENT ON COLUMN template_shares.coach_id IS 'Coach sharing the template';
COMMENT ON COLUMN template_shares.student_id IS 'Student receiving the template';
COMMENT ON COLUMN template_shares.master_template_id IS 'Original template being shared';
COMMENT ON COLUMN template_shares.student_template_id IS 'Copy created for the student';
COMMENT ON COLUMN template_shares.created_at IS 'Share creation timestamp';

-- chart_preferences
COMMENT ON COLUMN chart_preferences.user_id IS 'User who set the preference';
COMMENT ON COLUMN chart_preferences.exercise_id IS 'Exercise the preference applies to';
COMMENT ON COLUMN chart_preferences.chart_type IS 'Preferred chart type for visualization';
COMMENT ON COLUMN chart_preferences.created_at IS 'Preference creation timestamp';

-- exercise_translations
COMMENT ON COLUMN exercise_translations.exercise_id IS 'Exercise being translated';
COMMENT ON COLUMN exercise_translations.locale IS 'Language/locale code (e.g., en, es, fr)';
COMMENT ON COLUMN exercise_translations.name IS 'Translated exercise name';
COMMENT ON COLUMN exercise_translations.instructions IS 'Translated exercise instructions';