-- Suspicious entries in a training log (heart-api#42): found by a sweep pg_cron
-- runs, resolved by the user. Nothing here changes what was logged: an entry
-- the user calls invalid stays in the log and drops out of what is counted.

DROP TABLE IF EXISTS anomalies;

CREATE TABLE IF NOT EXISTS anomalies
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    workout_id  UUID        NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
    set_id      UUID REFERENCES exercise_sets (id) ON DELETE CASCADE,
    reason      TEXT        NOT NULL,
    observed    JSONB       NOT NULL,
    typical     REAL,
    status      TEXT        NOT NULL DEFAULT 'pending',
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,

    CONSTRAINT anomalies_reason_check CHECK (
        reason IN ('duration_left_running', 'outlier_weight', 'implausible_reps', 'swap_suspected')
    ),
    CONSTRAINT anomalies_status_check CHECK (status IN ('pending', 'valid', 'invalid')),
    CONSTRAINT anomalies_resolved_check CHECK ((status = 'pending') = (resolved_at IS NULL)),
    CONSTRAINT anomalies_subject_check CHECK ((reason = 'duration_left_running') = (set_id IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS anomalies_set_idx ON anomalies (set_id) WHERE set_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS anomalies_workout_duration_idx ON anomalies (workout_id) WHERE set_id IS NULL;
CREATE INDEX IF NOT EXISTS anomalies_workout_idx ON anomalies (workout_id);
CREATE INDEX IF NOT EXISTS anomalies_user_detected_idx ON anomalies (user_id, detected_at, id);

COMMENT ON TABLE anomalies IS
    'Suspicious entries in a user''s log, found by _sweep_anomalies: a set or a workout, why, and what the user made of it. Never a correction';
COMMENT ON COLUMN anomalies.user_id IS 'Whose log it is in';
COMMENT ON COLUMN anomalies.workout_id IS 'The workout it is in: the subject for a duration, the set''s workout otherwise';
COMMENT ON COLUMN anomalies.set_id IS 'The set it is about; null for a workout''s duration';
COMMENT ON COLUMN anomalies.reason IS
    'Which rule found it: duration_left_running, outlier_weight, implausible_reps or swap_suspected';
COMMENT ON COLUMN anomalies.observed IS
    'What was entered when it was judged: {"weight", "reps"} for a set, {"seconds"} for a workout. A resolution holds while the entry still reads this';
COMMENT ON COLUMN anomalies.typical IS
    'The exercise''s median working weight it was judged against; null for a duration';
COMMENT ON COLUMN anomalies.status IS
    'pending until the user decides: valid (it stands and counts), invalid (it stays in the log and drops out of every count)';
COMMENT ON COLUMN anomalies.detected_at IS 'When it was found, or found again after the entry was edited';
COMMENT ON COLUMN anomalies.resolved_at IS 'When the user last changed their decision; null while pending';
COMMENT ON CONSTRAINT anomalies_reason_check ON anomalies IS
    'The rules there are; a new one widens this';
COMMENT ON CONSTRAINT anomalies_status_check ON anomalies IS 'Undecided, or what the user decided';
COMMENT ON CONSTRAINT anomalies_resolved_check ON anomalies IS 'Resolved exactly when it is not pending';
COMMENT ON CONSTRAINT anomalies_subject_check ON anomalies IS
    'A duration is the workout''s; every other reason is one set''s';
COMMENT ON INDEX anomalies_set_idx IS
    'One finding per set: judged again under another rule, it is the same question and keeps its answer';
COMMENT ON INDEX anomalies_workout_duration_idx IS 'One finding per workout''s duration';
COMMENT ON INDEX anomalies_workout_idx IS 'What deleting a workout cascades through';
COMMENT ON INDEX anomalies_user_detected_idx IS 'The owner''s anomalies, newest found first';

DROP TABLE IF EXISTS anomaly_sweeps;

CREATE TABLE IF NOT EXISTS anomaly_sweeps
(
    id       BOOLEAN     DEFAULT true PRIMARY KEY,
    swept_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT anomaly_sweeps_one_row_check CHECK (id)
);

COMMENT ON TABLE anomaly_sweeps IS
    'When _sweep_anomalies last ran, so the next one reads only the users who wrote since; one row';
COMMENT ON COLUMN anomaly_sweeps.id IS 'Always true: the key that keeps it to one row';
COMMENT ON COLUMN anomaly_sweeps.swept_at IS 'When the last sweep started';
COMMENT ON CONSTRAINT anomaly_sweeps_one_row_check ON anomaly_sweeps IS 'One row';

CREATE INDEX IF NOT EXISTS workouts_updated_idx ON workouts (updated_at);

COMMENT ON INDEX workouts_updated_idx IS 'Workouts by when they last changed, across users: who wrote since a moment';

-- One user's log judged whole, since a new session moves the baseline every
-- other set is read against. The rules, kept conservative so that a flag is
-- worth a look:
--
-- - duration_left_running: a finished workout over 6 hours, less its pauses,
--   timed from its start, or its creation where no start was kept, as the
--   counts of time are
-- - outlier_weight: a working set over 2.5 times, or under 0.4 times, the
--   exercise's median working weight, once the exercise has 8 such sets; not
--   for bodyweight work, where the weight is help or extra load and a change
--   in it is the progress
-- - implausible_reps: over 100 reps on a loaded set
-- - swap_suspected: either of the two above, where the reps read as a weight
--   would be in line and the weight would read as a whole rep count; named
--   instead of them
--
-- A set the user called invalid counts for nothing, the median included.
--
-- One finding per entry, updating its row: the same entry keeps what the user
-- decided, even judged under another rule as the median moves; an edited one
-- is pending again. A row is written only when something in it changed. A
-- pending row no rule finds any more goes, and so does a resolved one whose
-- entry was edited since.
DROP FUNCTION IF EXISTS _detect_anomalies(TEXT);

CREATE OR REPLACE FUNCTION _detect_anomalies(_user_id TEXT)
    RETURNS INTEGER
    LANGUAGE sql
AS
$$
WITH _sets AS (
    SELECT
        s.id AS set_id,
        we.workout_id,
        we.exercise_id,
        s.weight,
        s.reps,
        e.category IN ('Weighted Body Weight', 'Assisted Body Weight') AS bodyweight,
        EXISTS (
            SELECT 1 FROM anomalies a WHERE a.set_id = s.id AND a.status = 'invalid'
        ) AS invalid
    FROM exercise_sets s
    JOIN workout_exercises we ON we.id = s.workout_exercise_id
    JOIN workouts w ON w.id = we.workout_id
    JOIN exercises e ON e.id = we.exercise_id
    WHERE w.user_id = _user_id
      AND s.completed
      AND s.set_type IS DISTINCT FROM 'w'
), _baseline AS (
    SELECT exercise_id, percentile_cont(0.5) WITHIN GROUP (ORDER BY weight) AS median, count(*) AS sets
    FROM _sets
    WHERE weight > 0
      AND NOT bodyweight
      AND NOT invalid
    GROUP BY exercise_id
), _judged AS (
    SELECT
        s.*,
        b.median,
        coalesce(b.sets >= 8 AND s.weight > 0 AND (s.weight > 2.5 * b.median OR s.weight < 0.4 * b.median), false)
            AS weight_out,
        coalesce(s.weight > 0 AND s.reps > 100, false) AS reps_out,
        coalesce(
            b.sets >= 8
                AND s.weight > 0
                AND s.weight <= 100
                AND abs(s.weight - round(s.weight)) < 0.01
                AND s.reps BETWEEN 0.4 * b.median AND 2.5 * b.median,
            false
        ) AS swap_fits
    FROM _sets s
    LEFT JOIN _baseline b USING (exercise_id)
), _set_findings AS (
    SELECT
        workout_id,
        set_id,
        CASE
            WHEN swap_fits THEN 'swap_suspected'
            WHEN weight_out THEN 'outlier_weight'
            ELSE 'implausible_reps'
        END AS reason,
        jsonb_build_object('weight', weight, 'reps', reps) AS observed,
        median::real AS typical
    FROM _judged
    WHERE weight_out OR reps_out
), _workouts AS (
    SELECT
        w.id AS workout_id,
        jsonb_build_object(
            'seconds',
            (extract(EPOCH FROM w.completed_at - coalesce(w.started_at, w.created_at)) - coalesce((
                SELECT sum(extract(EPOCH FROM (p ->> 'end')::timestamptz - (p ->> 'start')::timestamptz))
                FROM jsonb_array_elements(w.pauses) p
            ), 0))::bigint
        ) AS observed
    FROM workouts w
    WHERE w.user_id = _user_id
      AND w.completed_at IS NOT NULL
), _workout_findings AS (
    SELECT workout_id, observed
    FROM _workouts
    WHERE (observed ->> 'seconds')::bigint > 6 * 3600
), _set_upserts AS (
    INSERT INTO anomalies AS a (user_id, workout_id, set_id, reason, observed, typical)
    SELECT _user_id, workout_id, set_id, reason, observed, typical
    FROM _set_findings
    ON CONFLICT (set_id) WHERE set_id IS NOT NULL DO UPDATE
    SET reason      = excluded.reason,
        typical     = excluded.typical,
        observed    = excluded.observed,
        status      = CASE WHEN a.observed = excluded.observed THEN a.status ELSE 'pending' END,
        resolved_at = CASE WHEN a.observed = excluded.observed THEN a.resolved_at END,
        detected_at = CASE WHEN a.observed = excluded.observed THEN a.detected_at ELSE now() END
    WHERE (a.reason, a.observed, a.typical) IS DISTINCT FROM (excluded.reason, excluded.observed, excluded.typical)
), _workout_upserts AS (
    INSERT INTO anomalies AS a (user_id, workout_id, reason, observed)
    SELECT _user_id, workout_id, 'duration_left_running', observed
    FROM _workout_findings
    ON CONFLICT (workout_id) WHERE set_id IS NULL DO UPDATE
    SET observed    = excluded.observed,
        status      = 'pending',
        resolved_at = NULL,
        detected_at = now()
    WHERE a.observed IS DISTINCT FROM excluded.observed
), _stale AS (
    DELETE FROM anomalies a
    WHERE a.user_id = _user_id
      AND NOT EXISTS (
        SELECT 1 FROM _set_findings f WHERE f.set_id = a.set_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM _workout_findings f WHERE a.set_id IS NULL AND f.workout_id = a.workout_id
      )
      AND (
        a.status = 'pending'
        -- what the user decided was about an entry that has since changed
        OR a.observed IS DISTINCT FROM CASE
            WHEN a.set_id IS NULL THEN (SELECT observed FROM _workouts o WHERE o.workout_id = a.workout_id)
            ELSE (
                SELECT jsonb_build_object('weight', s.weight, 'reps', s.reps)
                FROM exercise_sets s
                WHERE s.id = a.set_id
            )
        END
      )
)
-- the writes above run whether read or not
SELECT ((SELECT count(*) FROM _set_findings) + (SELECT count(*) FROM _workout_findings))::int
$$;

COMMENT ON FUNCTION _detect_anomalies(TEXT) IS
    'Judges one user''s whole log against the anomaly rules, recording what it finds and keeping what the user decided about entries unchanged since. Returns how many it found';

-- What pg_cron runs: every user who wrote since the last sweep, all of them
-- the first time, each judged on their own so one failure is only theirs. The window reaches back 10 minutes past the last sweep's
-- start, so a write committed while it ran is read next time; judging a
-- user twice changes nothing.
DROP FUNCTION IF EXISTS _sweep_anomalies();

CREATE OR REPLACE FUNCTION _sweep_anomalies()
    RETURNS INTEGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    _since   TIMESTAMPTZ;
    _started TIMESTAMPTZ := now();
    _user    TEXT;
    _users   INTEGER     := 0;
BEGIN
    SELECT swept_at INTO _since FROM anomaly_sweeps;
    FOR _user IN
        SELECT DISTINCT user_id
        FROM workouts
        WHERE _since IS NULL
           OR updated_at > _since - interval '10 minutes'
        LOOP
            BEGIN
                PERFORM _detect_anomalies(_user);
                _users := _users + 1;
            EXCEPTION
                WHEN OTHERS THEN
                    -- one log that fails to judge (a workout deleted under the
                    -- sweep, say) leaves everyone else's judged; it is read
                    -- again when its user next writes
                    RAISE WARNING '_sweep_anomalies: % for user %', SQLERRM, _user;
            END;
        END LOOP;
    INSERT INTO anomaly_sweeps (swept_at)
    VALUES (_started)
    ON CONFLICT (id) DO UPDATE
    SET swept_at = excluded.swept_at;
    RETURN _users;
END
$$;

COMMENT ON FUNCTION _sweep_anomalies() IS
    'Runs _detect_anomalies for every user who wrote a workout since the last sweep (everyone the first time), each in its own subtransaction: a user whose log fails to judge is warned about and skipped. Returns how many users it judged';
