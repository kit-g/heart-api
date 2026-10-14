-- A history move refuses a target whose sets cannot hold the source's: sets
-- are kept in the columns their exercise's category reads, so reps moved onto
-- a distance-and-time exercise would sit where nothing reads them. The check
-- runs before the writes, so a dry run refuses exactly as the move does.

DROP FUNCTION IF EXISTS _move_exercise_history(TEXT, UUID, UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION _move_exercise_history(
    _user_id TEXT,
    _source_id UUID,
    _target_id UUID,
    _dry_run BOOLEAN DEFAULT false
)
    RETURNS TABLE (
        workout_exercises_moved  INTEGER,
        template_exercises_moved INTEGER,
        preferences_moved        INTEGER,
        preferences_dropped      INTEGER,
        chart_preferences_moved  INTEGER,
        goals_moved              INTEGER,
        source_deleted           BOOLEAN
    )
    LANGUAGE plpgsql
AS
$$
DECLARE
    _source_user_id  TEXT;
    _source_category TEXT;
    _target_category TEXT;
    _we_moved        INTEGER;
    _te_moved        INTEGER;
    _pref_moved      INTEGER;
    _pref_dropped    INTEGER;
    _chart_moved     INTEGER;
    _goals_moved     INTEGER;
    _deleted         BOOLEAN := false;
BEGIN
    IF _source_id = _target_id THEN
        RAISE EXCEPTION 'source and target are the same exercise'
            USING ERRCODE = 'invalid_parameter_value', DETAIL = _source_id::text;
    END IF;

    -- An exercise the user may reference is the library's or their own. Someone
    -- else's custom is reported exactly like a missing id, so the call cannot be
    -- used to confirm that it exists. The row is locked: a workout saved
    -- meanwhile that still names the source waits here, then meets the moved
    -- rows (or the deleted custom) instead of slipping in between the re-key
    -- and the delete.
    SELECT user_id, category
    INTO _source_user_id, _source_category
    FROM exercises
    WHERE id = _source_id
    AND (user_id IS NULL OR user_id = _user_id)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'exercise not found'
            USING ERRCODE = 'no_data_found', DETAIL = _source_id::text;
    END IF;

    SELECT category
    INTO _target_category
    FROM exercises
    WHERE id = _target_id
    AND (user_id IS NULL OR user_id = _user_id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'exercise not found'
            USING ERRCODE = 'no_data_found', DETAIL = _target_id::text;
    END IF;

    -- A set is kept in the columns its exercise's category reads; moved sets
    -- under a category with other columns would hold values nothing reads.
    -- The four load-by-reps categories share weight and reps; every other
    -- category, an unknown one included, holds only its own. Assisted body
    -- weight shares the columns but not their meaning, its weight being the
    -- assistance and not the load, so it moves only onto its own kind.
    IF _source_category IS DISTINCT FROM _target_category
        AND NOT (
            _source_category IN ('Barbell', 'Dumbbell', 'Machine', 'Weighted Body Weight')
            AND _target_category IN ('Barbell', 'Dumbbell', 'Machine', 'Weighted Body Weight')
        )
    THEN
        RAISE EXCEPTION 'the target''s sets cannot hold the source''s'
            USING ERRCODE = 'datatype_mismatch',
                DETAIL = format('%s cannot move onto %s', _source_category, _target_category);
    END IF;

    BEGIN
        UPDATE workout_exercises we
        SET exercise_id = _target_id
        FROM workouts w
        WHERE w.id = we.workout_id
        AND w.user_id = _user_id
        AND we.exercise_id = _source_id;
        GET DIAGNOSTICS _we_moved = ROW_COUNT;

        -- A routine the user shared is still the user's routine; the students'
        -- copies are their own templates and are not touched.
        UPDATE template_exercises te
        SET exercise_id = _target_id
        FROM templates t
        WHERE t.id = te.template_id
        AND t.user_id = _user_id
        AND te.exercise_id = _source_id;
        GET DIAGNOSTICS _te_moved = ROW_COUNT;

        -- Target wins: one row per (user, exercise), and the user chose the
        -- target because it is the one they use.
        DELETE FROM exercise_preferences
        WHERE user_id = _user_id
        AND exercise_id = _source_id
        AND EXISTS (
            SELECT 1
            FROM exercise_preferences
            WHERE user_id = _user_id
            AND exercise_id = _target_id
        );
        GET DIAGNOSTICS _pref_dropped = ROW_COUNT;

        WITH _moved AS (
            UPDATE exercise_preferences
            SET exercise_id = _target_id
            WHERE user_id = _user_id
            AND exercise_id = _source_id
            RETURNING chart_type
        )
        SELECT count(*), count(chart_type)
        INTO _pref_moved, _chart_moved
        FROM _moved;

        UPDATE goals
        SET exercise_id = _target_id
        WHERE user_id = _user_id
        AND exercise_id = _source_id;
        GET DIAGNOSTICS _goals_moved = ROW_COUNT;

        -- Last, after every row of the owner's was re-keyed: the FKs from
        -- workout_exercises and template_exercises RESTRICT, so a reference the
        -- updates above missed fails the move instead of being cascaded away.
        IF _source_user_id IS NOT NULL THEN
            DELETE FROM exercises
            WHERE id = _source_id;
            _deleted := true;
        END IF;

        IF _dry_run THEN
            RAISE EXCEPTION 'dry run' USING ERRCODE = 'DRY00';
        END IF;
    EXCEPTION
        WHEN SQLSTATE 'DRY00' THEN
            -- the block's writes are rolled back; the counts, being variables, stay
            NULL;
    END;

    RETURN QUERY SELECT _we_moved, _te_moved, _pref_moved, _pref_dropped, _chart_moved, _goals_moved, _deleted;
END
$$;

COMMENT ON FUNCTION _move_exercise_history(TEXT, UUID, UUID, BOOLEAN) IS
    'Re-keys one user''s workout exercises, template exercises, preferences and goals from the source exercise to the target, then deletes the source if the user owns it; a dry run returns the same counts and writes nothing. Both exercises must be the library''s or the user''s own (no_data_found otherwise); source and target must differ (invalid_parameter_value); the target''s category must keep sets in the source''s columns, the four load-by-reps categories being interchangeable (datatype_mismatch otherwise). Where the user has a preference row on both, the target''s is kept and the source''s counted as dropped.';
