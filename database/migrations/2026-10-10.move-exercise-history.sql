-- Moving one user's history from one exercise to another: every row of theirs
-- keyed on the source exercise (logged workouts, routines, per-exercise
-- preferences, goals) is re-keyed on the target, and a source the user owns is
-- deleted afterwards. A library exercise is never deleted. Where the user has a
-- preference row on both, the target's row is kept and the source's dropped,
-- and the drop is counted so a preview can say so. Nothing else in the schema
-- is unique per (user, exercise), so everything else moves whole: a workout or
-- routine that held both exercises holds the target twice afterwards, a goal on
-- each stays two goals.
--
-- The preview and the move are one code path. The writes run and are counted;
-- a dry run then raises out of the block, which rolls the writes back and keeps
-- the counts. A preview can therefore never disagree with the move it predicts.

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
    _source_user_id TEXT;
    _we_moved       INTEGER;
    _te_moved       INTEGER;
    _pref_moved     INTEGER;
    _pref_dropped   INTEGER;
    _chart_moved    INTEGER;
    _goals_moved    INTEGER;
    _deleted        BOOLEAN := false;
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
    SELECT user_id
    INTO _source_user_id
    FROM exercises
    WHERE id = _source_id
    AND (user_id IS NULL OR user_id = _user_id)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'exercise not found'
            USING ERRCODE = 'no_data_found', DETAIL = _source_id::text;
    END IF;

    PERFORM 1
    FROM exercises
    WHERE id = _target_id
    AND (user_id IS NULL OR user_id = _user_id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'exercise not found'
            USING ERRCODE = 'no_data_found', DETAIL = _target_id::text;
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
    'Re-keys one user''s workout exercises, template exercises, preferences and goals from the source exercise to the target, then deletes the source if the user owns it; a dry run returns the same counts and writes nothing. Both exercises must be the library''s or the user''s own (no_data_found otherwise); source and target must differ (invalid_parameter_value). Where the user has a preference row on both, the target''s is kept and the source''s counted as dropped.';
