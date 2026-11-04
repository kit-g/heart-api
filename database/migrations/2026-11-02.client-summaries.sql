-- A row per coach relationship with what a roster shows, since a read-time roster
-- of a thousand clients would mean a thousand folds. Anything that changes the
-- answer marks it dirty, and the next read works it out again, so a coach pays only
-- for what changed since they last looked.

DROP TABLE IF EXISTS client_summaries;

CREATE TABLE IF NOT EXISTS client_summaries
(
    connection_id   UUID PRIMARY KEY REFERENCES connections (id) ON DELETE CASCADE,
    coach_id        TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    student_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    dirty           BOOLEAN     NOT NULL DEFAULT true,
    generation      BIGINT      NOT NULL DEFAULT 0,
    program_id      UUID,
    program_name    TEXT,
    program_week    INTEGER,
    program_weeks   INTEGER,
    ending          BOOLEAN     NOT NULL DEFAULT false,
    recent          TIMESTAMPTZ[] NOT NULL DEFAULT '{}',
    last_trained_at TIMESTAMPTZ,
    lighter_at      TIMESTAMPTZ,
    note_at         TIMESTAMPTZ,
    reviewed_at     TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS client_summaries_coach_idx ON client_summaries (coach_id, connection_id);
CREATE INDEX IF NOT EXISTS client_summaries_student_idx ON client_summaries (student_id);

COMMENT ON TABLE client_summaries IS 'What a roster shows of one client, from what their coach can read';
COMMENT ON COLUMN client_summaries.connection_id IS 'The relationship';
COMMENT ON COLUMN client_summaries.coach_id IS 'The coach';
COMMENT ON COLUMN client_summaries.student_id IS 'The client';
COMMENT ON COLUMN client_summaries.dirty IS 'Something changed since this was worked out';
COMMENT ON COLUMN client_summaries.generation IS
    'Moves with each change, so working this out over a change still being written leaves it dirty';
COMMENT ON COLUMN client_summaries.program_id IS 'The program of this coach''s they are on; a link, not a reference';
COMMENT ON COLUMN client_summaries.program_name IS 'Its name';
COMMENT ON COLUMN client_summaries.program_week IS 'The week the coach can see them in';
COMMENT ON COLUMN client_summaries.program_weeks IS 'How long it runs; NULL if it runs on';
COMMENT ON COLUMN client_summaries.ending IS 'It ends within a week';
COMMENT ON COLUMN client_summaries.recent IS 'When they trained in the last 14 days; the coach''s device turns these into days';
COMMENT ON COLUMN client_summaries.last_trained_at IS 'When they last trained, as far as the coach can see';
COMMENT ON COLUMN client_summaries.lighter_at IS 'The last workout that fell short of what was planned';
COMMENT ON COLUMN client_summaries.note_at IS 'The last workout with a note';
COMMENT ON COLUMN client_summaries.reviewed_at IS 'When the coach last looked; a reason counts only what came after it';
COMMENT ON COLUMN client_summaries.updated_at IS 'When this was last worked out';
COMMENT ON INDEX client_summaries_coach_idx IS 'One coach''s roster';
COMMENT ON INDEX client_summaries_student_idx IS 'Finding the rows of a student whose data changed';

INSERT INTO client_summaries (connection_id, coach_id, student_id)
SELECT
    id,
    CASE WHEN initiator_role = 'COACH' THEN initiator_id ELSE target_id END,
    CASE WHEN initiator_role = 'COACH' THEN target_id ELSE initiator_id END
FROM connections
WHERE 'COACH' IN (initiator_role, target_role)
  AND accepted_at IS NOT NULL;

CREATE OR REPLACE FUNCTION _track_client_summary() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF 'COACH' IN (NEW.initiator_role, NEW.target_role) AND NEW.accepted_at IS NOT NULL THEN
        INSERT INTO client_summaries (connection_id, coach_id, student_id)
        VALUES (
            NEW.id,
            CASE WHEN NEW.initiator_role = 'COACH' THEN NEW.initiator_id ELSE NEW.target_id END,
            CASE WHEN NEW.initiator_role = 'COACH' THEN NEW.target_id ELSE NEW.initiator_id END
        )
        ON CONFLICT (connection_id) DO UPDATE
            SET dirty = true,
                generation = client_summaries.generation + 1,
                coach_id = EXCLUDED.coach_id,
                student_id = EXCLUDED.student_id;
    ELSE
        DELETE FROM client_summaries WHERE connection_id = NEW.id;
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _track_client_summary() IS 'Keeps a summary for each accepted coach relationship, marked to be worked out again';

DROP TRIGGER IF EXISTS connections_track_summary ON connections;
CREATE TRIGGER connections_track_summary
    AFTER INSERT OR UPDATE OF status, shares, accepted_at, initiator_role, target_role
    ON connections
    FOR EACH ROW
EXECUTE FUNCTION _track_client_summary();

COMMENT ON TRIGGER connections_track_summary ON connections IS 'A pause, a share or a new start changes what a coach can read';

CREATE OR REPLACE FUNCTION _mark_summaries_by_user() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE client_summaries
    SET dirty = true,
        generation = generation + 1
    WHERE student_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _mark_summaries_by_user() IS 'Marks the summaries of the user a changed row belongs to; for most users that is no row at all';

DROP TRIGGER IF EXISTS workouts_mark_summaries ON workouts;
CREATE TRIGGER workouts_mark_summaries
    AFTER INSERT OR UPDATE OR DELETE
    ON workouts
    FOR EACH ROW
EXECUTE FUNCTION _mark_summaries_by_user();

DROP TRIGGER IF EXISTS skips_mark_summaries ON skips;
CREATE TRIGGER skips_mark_summaries
    AFTER INSERT OR UPDATE OR DELETE
    ON skips
    FOR EACH ROW
EXECUTE FUNCTION _mark_summaries_by_user();

DROP TRIGGER IF EXISTS programs_mark_summaries ON programs;
CREATE TRIGGER programs_mark_summaries
    AFTER INSERT OR UPDATE OR DELETE
    ON programs
    FOR EACH ROW
EXECUTE FUNCTION _mark_summaries_by_user();

DROP TRIGGER IF EXISTS program_actions_mark_summaries ON program_actions;
CREATE TRIGGER program_actions_mark_summaries
    AFTER INSERT OR UPDATE OR DELETE
    ON program_actions
    FOR EACH ROW
EXECUTE FUNCTION _mark_summaries_by_user();

COMMENT ON TRIGGER workouts_mark_summaries ON workouts IS 'A workout saved, edited, deleted, hidden or unhidden';
COMMENT ON TRIGGER skips_mark_summaries ON skips IS 'A skip';
COMMENT ON TRIGGER programs_mark_summaries ON programs IS 'A program changed';
COMMENT ON TRIGGER program_actions_mark_summaries ON program_actions IS 'A step taken in a program';

CREATE OR REPLACE FUNCTION _mark_summaries_by_workout_plan() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE client_summaries s
    SET dirty = true,
        generation = s.generation + 1
    FROM workouts w
    WHERE w.id = NEW.workout_id
      AND s.student_id = w.user_id;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _mark_summaries_by_workout_plan() IS 'A plan arriving after its workout can make it lighter than planned';

DROP TRIGGER IF EXISTS workout_plans_mark_summaries ON workout_plans;
CREATE TRIGGER workout_plans_mark_summaries
    AFTER INSERT
    ON workout_plans
    FOR EACH ROW
EXECUTE FUNCTION _mark_summaries_by_workout_plan();

COMMENT ON TRIGGER workout_plans_mark_summaries ON workout_plans IS 'What was planned arrived';

CREATE OR REPLACE FUNCTION _owe_workout_digest() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO push_digests (user_id, topic)
    SELECT c.coach_id, 'coaching.workout_digest'
    FROM client_summaries c
    JOIN connections x ON x.id = c.connection_id
    WHERE c.student_id = NEW.user_id
      AND x.status = 'active'
      AND NOT _blocked_between(c.coach_id, c.student_id)
    ON CONFLICT (user_id, topic) DO NOTHING;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _owe_workout_digest() IS 'Owes a coach their daily push when a client finishes a workout they can see';

DROP TRIGGER IF EXISTS workouts_owe_digest ON workouts;
CREATE TRIGGER workouts_owe_digest
    AFTER INSERT OR UPDATE OF completed_at
    ON workouts
    FOR EACH ROW
    WHEN (NEW.completed_at IS NOT NULL AND NEW.hidden_at IS NULL)
EXECUTE FUNCTION _owe_workout_digest();

COMMENT ON TRIGGER workouts_owe_digest ON workouts IS 'A finished workout that is not hidden';

-- Whether a workout fell short of what was planned. A plan names its sets as
-- {"exercises": [{"sets": [{"weight": 80, "setId": "..."}]}]}: a planned set with no
-- set of this workout, one not completed, or one lighter than planned. The plan is the
-- device's, so anything else in it, however it got there, compares as nothing.
CREATE OR REPLACE FUNCTION _workout_fell_short(_workout_id UUID) RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
AS
$$
SELECT EXISTS (
    SELECT 1
    FROM workout_plans p
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(p.plan -> 'exercises') = 'array' THEN p.plan -> 'exercises' ELSE '[]'::jsonb END
    ) exercise
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(exercise -> 'sets') = 'array' THEN exercise -> 'sets' ELSE '[]'::jsonb END
    ) planned
    LEFT JOIN exercise_sets done
        ON done.id = CASE
            WHEN planned ->> 'setId' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            THEN (planned ->> 'setId')::uuid
        END
        AND EXISTS (
            SELECT 1
            FROM workout_exercises we
            WHERE we.id = done.workout_exercise_id
              AND we.workout_id = p.workout_id
        )
    WHERE p.workout_id = _workout_id
      AND jsonb_typeof(planned) = 'object'
      AND (
        done.id IS NULL
        OR NOT coalesce(done.completed, false)
        OR done.weight < CASE
            WHEN jsonb_typeof(planned -> 'weight') = 'number' THEN (planned ->> 'weight')::real
        END
      )
)
$$;

COMMENT ON FUNCTION _workout_fell_short(UUID) IS 'Whether a workout fell short of its plan; a workout with no plan never does';

CREATE OR REPLACE FUNCTION _mark_all_client_summaries() RETURNS VOID
    LANGUAGE sql
AS
$$
UPDATE client_summaries
SET dirty = true,
    generation = generation + 1
WHERE program_id IS NOT NULL
$$;

COMMENT ON FUNCTION _mark_all_client_summaries() IS 'Marks summaries on a program, since a calendar week can move one along with nothing changing';
