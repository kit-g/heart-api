-- The stretches a workout spent paused, as true wall-clock intervals:
--
--   workouts.pauses  a JSON array of {"start", "end"} ISO instants, in order;
--                    '[]' when the workout never paused.
--
-- started_at and completed_at stay the real start and finish. A pause is
-- subtracted from the workout's length, never hidden by moving either end, so
-- a reader can tell when a session stopped and not only for how long.
--
-- Every row older than this migration and every import has no pauses, which
-- is what '[]' says; there is no "unknown" for NULL to mean.
--
-- Dropped and rebuilt on a re-run while unshipped; once deployed it holds
-- user data, and changing it is a new migration.

-- Whether _pauses is a well-formed list of pauses for a workout running from
-- _start to _end: each pause ends after it starts, falls inside the workout
-- (only after _start while _end is NULL), and none overlaps the next. Touching
-- ends are fine. Declared IMMUTABLE for the CHECK below: the cast reads each
-- instant's own offset, so the session time zone never changes the answer.
CREATE OR REPLACE FUNCTION _pauses_fit(_pauses JSONB, _start TIMESTAMPTZ, _end TIMESTAMPTZ) RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE AS
$$
SELECT jsonb_typeof(_pauses) = 'array'
   AND jsonb_array_length(_pauses) <= 100
   AND NOT EXISTS (
       SELECT 1
       FROM (
           SELECT
               (p ->> 'start')::timestamptz AS pause_start,
               (p ->> 'end')::timestamptz AS pause_end,
               lag((p ->> 'end')::timestamptz) OVER (ORDER BY (p ->> 'start')::timestamptz) AS previous_end
           FROM jsonb_array_elements(_pauses) p
       ) i
       WHERE (
           i.pause_start < i.pause_end
           AND (_start IS NULL OR i.pause_start >= _start)
           AND (_end IS NULL OR i.pause_end <= _end)
           AND (i.previous_end IS NULL OR i.previous_end <= i.pause_start)
       ) IS NOT TRUE
   )
$$;

COMMENT ON FUNCTION _pauses_fit(JSONB, TIMESTAMPTZ, TIMESTAMPTZ) IS
    'Whether a pauses array is ordered intervals inside the workout''s start..end that never overlap (at most 100)';

-- _pauses cut to a workout now running from _start to _end: a pause that
-- crosses either end is shortened to it, and one left with no length is
-- dropped. A pause already inside is kept exactly as written.
CREATE OR REPLACE FUNCTION _clip_pauses(_pauses JSONB, _start TIMESTAMPTZ, _end TIMESTAMPTZ) RETURNS JSONB
LANGUAGE SQL IMMUTABLE AS
$$
SELECT coalesce(
    jsonb_agg(
        CASE
            WHEN c.clipped_start = c.pause_start AND c.clipped_end = c.pause_end THEN c.p
            ELSE jsonb_build_object(
                'start', to_char(c.clipped_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
                'end', to_char(c.clipped_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
            )
        END
        ORDER BY c.clipped_start
    ),
    '[]'::jsonb
)
FROM (
    SELECT
        p,
        (p ->> 'start')::timestamptz AS pause_start,
        (p ->> 'end')::timestamptz AS pause_end,
        greatest((p ->> 'start')::timestamptz, _start) AS clipped_start,
        least((p ->> 'end')::timestamptz, _end) AS clipped_end
    FROM jsonb_array_elements(_pauses) p
) c
WHERE c.clipped_start < c.clipped_end
$$;

COMMENT ON FUNCTION _clip_pauses(JSONB, TIMESTAMPTZ, TIMESTAMPTZ) IS
    'A pauses array cut to a new start..end: crossing pauses shortened, empty ones dropped, the rest untouched';

ALTER TABLE workouts
    DROP COLUMN IF EXISTS pauses,
    ADD COLUMN IF NOT EXISTS pauses JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE workouts
    ADD CONSTRAINT workouts_pauses_check CHECK (_pauses_fit(pauses, started_at, completed_at));

COMMENT ON COLUMN workouts.pauses IS
    'Stretches spent paused, [{"start", "end"}] as ISO instants in order; [] when none. started_at and completed_at are never moved to hide one.';
COMMENT ON CONSTRAINT workouts_pauses_check ON workouts IS
    'Pauses are ordered, non-overlapping intervals inside the workout, and a session has at most 100.';

-- The pauses are a scalar column, so the archive carries them explicitly, as
-- it does calories and the note.
ALTER TABLE archive.deleted_workouts
    ADD COLUMN IF NOT EXISTS pauses JSONB;

COMMENT ON COLUMN archive.deleted_workouts.pauses IS
    'Stretches the session spent paused, as recorded at deletion time';

CREATE OR REPLACE FUNCTION _archive_workout() RETURNS TRIGGER AS
$$
BEGIN
    INSERT INTO archive.deleted_workouts (
        id,
        user_id,
        name,
        started_at,
        completed_at,
        created_at,
        calories,
        note,
        pauses,
        exercises
    ) VALUES (
        OLD.id,
        OLD.user_id,
        OLD.name,
        OLD.started_at,
        OLD.completed_at,
        OLD.created_at,
        OLD.calories,
        OLD.note,
        OLD.pauses,
        _workout_exercises(OLD.id)
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS 'Trigger function to archive workout data before deletion';
