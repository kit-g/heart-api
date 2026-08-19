-- Two guards on bulk-imported workouts, from the same ticket (#56):
--
-- 1. import_id became opaque: the source prefix survives for targeted cleanup
--    ('strong:%'), but the rest is now a sha256-derived token instead of raw
--    '<date>#<workout name>' — a dedup key ends up in URLs and logs, and its
--    old shape leaked user content and invited parsing. Comment-only change;
--    the column and its partial unique index are untouched.
--
-- 2. A hard ceiling on imported workouts per user, enforced by the database
--    itself so no write path — present or future — can grow an account's
--    imported history without bound. The API already truncates a single batch
--    to its most recent 10k workouts; this backstops accumulation across
--    requests (scripted re-imports of disjoint synthetic files).
--    Statement-level with a transition table: one cheap check per INSERT
--    statement, and the count only runs when the statement actually wrote
--    imported rows. App-created workouts (import_id IS NULL) are never
--    counted or blocked.

COMMENT ON COLUMN workouts.import_id IS
    'Deterministic opaque identity for bulk-imported workouts (''<source>:<16 hex of sha256 over the source row>''); unique per user, NULL for app-created workouts';

CREATE OR REPLACE FUNCTION assert_imported_workouts_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender TEXT;
BEGIN
    SELECT n.user_id
    INTO _offender
    FROM (
        SELECT DISTINCT user_id
        FROM new_rows
        WHERE import_id IS NOT NULL
    ) n
    WHERE (
        SELECT count(*)
        FROM workouts w
        WHERE w.user_id = n.user_id
          AND w.import_id IS NOT NULL
    ) > 20000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'imported workouts cap (20000) exceeded for user %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_imported_workouts_capped() IS
    'Statement-level AFTER INSERT guard on workouts: refuses the write when a user''s rows with import_id IS NOT NULL would exceed 20000. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS workouts_imported_cap ON workouts;
CREATE TRIGGER workouts_imported_cap
    AFTER INSERT
    ON workouts
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_imported_workouts_capped();

COMMENT ON TRIGGER workouts_imported_cap ON workouts IS
    'Per-user ceiling of 20000 bulk-imported workouts; app-created workouts (import_id IS NULL) are unaffected';

-- 3. A companion ceiling one level down: sets per workout, across every write
--    path (import and the app's own save). The gateway's 10MB body limit
--    still admits ~150k one-row sets aimed at a single workout; a real
--    workout tops out around a hundred. The import parser caps a workout at
--    500 sets before the DB ever sees it — this trigger is the backstop at
--    double that, so it never fires on anything legitimate. Same shape as
--    above: statement-level, transition table, index-only counting via
--    exercise_sets_workout_exercise_id_idx / workout_exercises_workout_id_idx.

CREATE OR REPLACE FUNCTION assert_workout_sets_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender UUID;
BEGIN
    SELECT we.workout_id
    INTO _offender
    FROM (
        SELECT DISTINCT workout_exercise_id
        FROM new_rows
    ) n
    JOIN workout_exercises we ON we.id = n.workout_exercise_id
    GROUP BY we.workout_id
    HAVING (
        SELECT count(*)
        FROM exercise_sets es
        JOIN workout_exercises we2 ON we2.id = es.workout_exercise_id
        WHERE we2.workout_id = we.workout_id
    ) > 1000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'sets per workout cap (1000) exceeded for workout %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_workout_sets_capped() IS
    'Statement-level AFTER INSERT guard on exercise_sets: refuses the write when any touched workout would hold more than 1000 sets. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS exercise_sets_workout_cap ON exercise_sets;
CREATE TRIGGER exercise_sets_workout_cap
    AFTER INSERT
    ON exercise_sets
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_workout_sets_capped();

COMMENT ON TRIGGER exercise_sets_workout_cap ON exercise_sets IS
    'Per-workout ceiling of 1000 sets, enforced for every write path';

-- 4. The same ceiling for the middle table: workout_exercises per workout.
--    The set trigger never fires on a body of set-less exercise entries, so
--    without this a 10MB request could park ~200k empty exercise rows on one
--    workout. Imports stay far below it (an exercise row exists only with at
--    least one set, and sets are parser-capped at 500/workout).

CREATE OR REPLACE FUNCTION assert_workout_exercises_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender UUID;
BEGIN
    SELECT n.workout_id
    INTO _offender
    FROM (
        SELECT DISTINCT workout_id
        FROM new_rows
    ) n
    WHERE (
        SELECT count(*)
        FROM workout_exercises we
        WHERE we.workout_id = n.workout_id
    ) > 1000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'exercises per workout cap (1000) exceeded for workout %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_workout_exercises_capped() IS
    'Statement-level AFTER INSERT guard on workout_exercises: refuses the write when any touched workout would hold more than 1000 exercise rows. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS workout_exercises_workout_cap ON workout_exercises;
CREATE TRIGGER workout_exercises_workout_cap
    AFTER INSERT
    ON workout_exercises
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_workout_exercises_capped();

COMMENT ON TRIGGER workout_exercises_workout_cap ON workout_exercises IS
    'Per-workout ceiling of 1000 exercise rows, enforced for every write path';

-- 5. Custom exercises per user. The import creates one custom per unmatched
--    name — and does so whether or not any workout lands, so replaying an
--    already-imported file with fresh synthetic names would grow the
--    exercises table without ever touching the workouts ceiling. A real
--    account holds dozens of customs; the messiest real export created ~100.
--    Global (library) exercises have user_id IS NULL and are never counted
--    or blocked, so content syncs are unaffected.

CREATE OR REPLACE FUNCTION assert_custom_exercises_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender TEXT;
BEGIN
    SELECT n.user_id
    INTO _offender
    FROM (
        SELECT DISTINCT user_id
        FROM new_rows
        WHERE user_id IS NOT NULL
    ) n
    WHERE (
        SELECT count(*)
        FROM exercises e
        WHERE e.user_id = n.user_id
    ) > 2000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'custom exercises cap (2000) exceeded for user %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_custom_exercises_capped() IS
    'Statement-level AFTER INSERT guard on exercises: refuses the write when a user would hold more than 2000 custom exercises. Globals (user_id IS NULL) are exempt. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS exercises_custom_cap ON exercises;
CREATE TRIGGER exercises_custom_cap
    AFTER INSERT
    ON exercises
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_custom_exercises_capped();

COMMENT ON TRIGGER exercises_custom_cap ON exercises IS
    'Per-user ceiling of 2000 custom exercises; global library rows (user_id IS NULL) are unaffected';

-- 6-7. Templates mirror workouts: _saveTemplate/_replaceTemplate expand the
--      request body's exercise and set arrays into rows the same way, so the
--      same pair of ceilings applies.

CREATE OR REPLACE FUNCTION assert_template_exercises_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender UUID;
BEGIN
    SELECT n.template_id
    INTO _offender
    FROM (
        SELECT DISTINCT template_id
        FROM new_rows
    ) n
    WHERE (
        SELECT count(*)
        FROM template_exercises te
        WHERE te.template_id = n.template_id
    ) > 1000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'exercises per template cap (1000) exceeded for template %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_template_exercises_capped() IS
    'Statement-level AFTER INSERT guard on template_exercises: refuses the write when any touched template would hold more than 1000 exercise rows. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS template_exercises_template_cap ON template_exercises;
CREATE TRIGGER template_exercises_template_cap
    AFTER INSERT
    ON template_exercises
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_template_exercises_capped();

COMMENT ON TRIGGER template_exercises_template_cap ON template_exercises IS
    'Per-template ceiling of 1000 exercise rows, enforced for every write path';

CREATE OR REPLACE FUNCTION assert_template_sets_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender UUID;
BEGIN
    SELECT te.template_id
    INTO _offender
    FROM (
        SELECT DISTINCT template_exercise_id
        FROM new_rows
    ) n
    JOIN template_exercises te ON te.id = n.template_exercise_id
    GROUP BY te.template_id
    HAVING (
        SELECT count(*)
        FROM template_exercise_sets tes
        JOIN template_exercises te2 ON te2.id = tes.template_exercise_id
        WHERE te2.template_id = te.template_id
    ) > 1000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'sets per template cap (1000) exceeded for template %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_template_sets_capped() IS
    'Statement-level AFTER INSERT guard on template_exercise_sets: refuses the write when any touched template would hold more than 1000 sets. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS template_exercise_sets_template_cap ON template_exercise_sets;
CREATE TRIGGER template_exercise_sets_template_cap
    AFTER INSERT
    ON template_exercise_sets
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_template_sets_capped();

COMMENT ON TRIGGER template_exercise_sets_template_cap ON template_exercise_sets IS
    'Per-template ceiling of 1000 sets, enforced for every write path';
