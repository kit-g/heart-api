-- Client summaries, tightened. A workout write marks summaries once per statement, so
-- an import of years is one update; a template marks them too, since a program's
-- sessions are its templates. A coach is owed a digest once per workout they can read
-- and didn't enter themselves. An ending keeps the date it began, and a relationship
-- that changes coach starts unreviewed.

ALTER TABLE IF EXISTS client_summaries
    DROP COLUMN IF EXISTS ending_since,
    ADD COLUMN IF NOT EXISTS ending_since TIMESTAMPTZ;

COMMENT ON COLUMN client_summaries.ending_since IS 'When it began to end; NULL while it doesn''t';

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
                -- another coach hasn't looked at anything yet
                reviewed_at = CASE
                    WHEN client_summaries.coach_id = EXCLUDED.coach_id THEN client_summaries.reviewed_at
                END,
                coach_id = EXCLUDED.coach_id,
                student_id = EXCLUDED.student_id;
    ELSE
        DELETE FROM client_summaries WHERE connection_id = NEW.id;
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _track_client_summary() IS
    'Keeps a summary for each accepted coach relationship, marked to be worked out again, and unreviewed when its coach changes';

-- One function for every event: each trigger names its transition table _changed,
-- the new rows on insert and update and the old ones on delete. An update keeps
-- user_id, so its new rows name the same people.
CREATE OR REPLACE FUNCTION _mark_summaries_by_changed_rows() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE client_summaries
    SET dirty = true,
        generation = generation + 1
    WHERE student_id IN (SELECT user_id FROM _changed);
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _mark_summaries_by_changed_rows() IS
    'Marks the summaries of the users a statement''s rows belong to, once per statement; for most users that is no row at all';

DROP TRIGGER IF EXISTS workouts_mark_summaries ON workouts;

DROP TRIGGER IF EXISTS workouts_mark_summaries_insert ON workouts;
CREATE TRIGGER workouts_mark_summaries_insert
    AFTER INSERT
    ON workouts
    REFERENCING NEW TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

DROP TRIGGER IF EXISTS workouts_mark_summaries_update ON workouts;
CREATE TRIGGER workouts_mark_summaries_update
    AFTER UPDATE
    ON workouts
    REFERENCING NEW TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

DROP TRIGGER IF EXISTS workouts_mark_summaries_delete ON workouts;
CREATE TRIGGER workouts_mark_summaries_delete
    AFTER DELETE
    ON workouts
    REFERENCING OLD TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

COMMENT ON TRIGGER workouts_mark_summaries_insert ON workouts IS 'Workouts saved';
COMMENT ON TRIGGER workouts_mark_summaries_update ON workouts IS 'Workouts edited, hidden or unhidden';
COMMENT ON TRIGGER workouts_mark_summaries_delete ON workouts IS 'Workouts deleted';

DROP TRIGGER IF EXISTS templates_mark_summaries_insert ON templates;
CREATE TRIGGER templates_mark_summaries_insert
    AFTER INSERT
    ON templates
    REFERENCING NEW TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

DROP TRIGGER IF EXISTS templates_mark_summaries_update ON templates;
CREATE TRIGGER templates_mark_summaries_update
    AFTER UPDATE
    ON templates
    REFERENCING NEW TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

DROP TRIGGER IF EXISTS templates_mark_summaries_delete ON templates;
CREATE TRIGGER templates_mark_summaries_delete
    AFTER DELETE
    ON templates
    REFERENCING OLD TABLE AS _changed
    FOR EACH STATEMENT
EXECUTE FUNCTION _mark_summaries_by_changed_rows();

COMMENT ON TRIGGER templates_mark_summaries_insert ON templates IS 'A session joining a program moves its cycles';
COMMENT ON TRIGGER templates_mark_summaries_update ON templates IS 'A session moving between programs or phases';
COMMENT ON TRIGGER templates_mark_summaries_delete ON templates IS 'A session leaving a program completes its cycle sooner';

-- A workout is owed once, when it is first finished: a later edit of a finished one
-- owes nothing. The coach is owed it only if they can read it, and not for one they
-- entered. Coaches are taken in one order, so two statements owing the same coaches
-- wait for each other instead of deadlocking.
CREATE OR REPLACE FUNCTION _owe_workout_digest() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _first UUID[];
BEGIN
    -- a statement plans every table it names, so the old rows are read only where
    -- they exist
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(n.id) INTO _first
        FROM _finished n
        JOIN _before b ON b.id = n.id
        WHERE b.completed_at IS NULL;
    ELSE
        SELECT array_agg(id) INTO _first FROM _finished;
    END IF;

    INSERT INTO push_digests (user_id, topic)
    SELECT DISTINCT c.coach_id, 'coaching.workout_digest'
    FROM _finished w
    JOIN client_summaries c ON c.student_id = w.user_id
    JOIN connections x ON x.id = c.connection_id
    WHERE w.id = ANY (_first)
      AND w.completed_at IS NOT NULL
      AND w.hidden_at IS NULL
      AND w.logged_by IS DISTINCT FROM c.coach_id
      AND x.status = 'active'
      AND _readable_at(_relation(c.coach_id, c.student_id), w.started_at, w.hidden_at)
    ORDER BY c.coach_id
    ON CONFLICT (user_id, topic) DO NOTHING;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _owe_workout_digest() IS
    'Owes a coach their daily push when a client first finishes a workout the coach can see and didn''t enter';

DROP TRIGGER IF EXISTS workouts_owe_digest ON workouts;

DROP TRIGGER IF EXISTS workouts_owe_digest_insert ON workouts;
CREATE TRIGGER workouts_owe_digest_insert
    AFTER INSERT
    ON workouts
    REFERENCING NEW TABLE AS _finished
    FOR EACH STATEMENT
EXECUTE FUNCTION _owe_workout_digest();

DROP TRIGGER IF EXISTS workouts_owe_digest_update ON workouts;
CREATE TRIGGER workouts_owe_digest_update
    AFTER UPDATE
    ON workouts
    REFERENCING OLD TABLE AS _before NEW TABLE AS _finished
    FOR EACH STATEMENT
EXECUTE FUNCTION _owe_workout_digest();

COMMENT ON TRIGGER workouts_owe_digest_insert ON workouts IS 'Workouts saved finished';
COMMENT ON TRIGGER workouts_owe_digest_update ON workouts IS 'Workouts finished since';

-- As before, with the planned weight compared as numeric: a JSON number past real's
-- range compares as a number instead of failing.
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
        OR done.weight::numeric < CASE
            WHEN jsonb_typeof(planned -> 'weight') = 'number' THEN (planned ->> 'weight')::numeric
        END
      )
)
$$;

COMMENT ON FUNCTION _workout_fell_short(UUID) IS 'Whether a workout fell short of its plan; a workout with no plan never does';

-- A program's week moves only when a cycle completes, never with the calendar, so
-- nothing needs marking by date.
DROP FUNCTION IF EXISTS _mark_all_client_summaries();
