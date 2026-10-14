-- Stages (heart-api#256): a stages rule moves an exercise through set schemes
-- on a miss, and the device records the move as a program action, `stage`,
-- naming the exercise, the slot when the rule is a slot's, the stage it moved
-- to and the workout that caused it. Deleting the workout deletes the stage.
-- A history move re-keys the exercise, as it does a ladder's advance.

ALTER TABLE IF EXISTS program_actions
    DROP COLUMN IF EXISTS exercise_id,
    DROP COLUMN IF EXISTS slot,
    DROP COLUMN IF EXISTS stage,
    ADD COLUMN IF NOT EXISTS exercise_id UUID,
    ADD COLUMN IF NOT EXISTS slot UUID,
    ADD COLUMN IF NOT EXISTS stage SMALLINT;

ALTER TABLE IF EXISTS program_actions
    DROP CONSTRAINT IF EXISTS program_actions_kind_check,
    ADD CONSTRAINT program_actions_kind_check CHECK (
        kind IN ('repeat', 'pause', 'resume', 'replay', 'lighter', 'advance', 'stage')
    ),
    DROP CONSTRAINT IF EXISTS program_actions_advance_check,
    ADD CONSTRAINT program_actions_advance_check CHECK (
        (kind = 'advance') = (from_exercise IS NOT NULL AND to_exercise IS NOT NULL)
        AND (workout_id IS NULL OR kind IN ('advance', 'stage'))
    ),
    DROP CONSTRAINT IF EXISTS program_actions_stage_check,
    ADD CONSTRAINT program_actions_stage_check CHECK (
        (kind = 'stage') = (exercise_id IS NOT NULL AND stage IS NOT NULL)
        AND (slot IS NULL OR kind = 'stage')
        AND (stage IS NULL OR stage BETWEEN 0 AND 19)
    );

COMMENT ON COLUMN program_actions.kind IS
    'repeat runs a cycle again at the same week; pause and resume step the program aside and back; replay goes back to week; lighter makes the open cycle a lighter one; advance is a ladder moving an exercise to its next rung; stage is a stages rule moving an exercise to another set scheme';
COMMENT ON COLUMN program_actions.exercise_id IS
    'The exercise a stage moved; not a reference: a history move re-keys it';
COMMENT ON COLUMN program_actions.slot IS
    'The template exercise whose own rule a stage moved, when the rule is a slot''s; null is the exercise''s rule';
COMMENT ON COLUMN program_actions.stage IS
    'The stage a stage action moved to, from 0; at most 20 stages, so at most 19';
COMMENT ON COLUMN program_actions.workout_id IS
    'The workout that caused an advance or a stage; deleting it deletes the action';
COMMENT ON CONSTRAINT program_actions_advance_check ON program_actions IS
    'An advance names both exercises, and only an advance names them; only an advance or a stage names a workout';
COMMENT ON CONSTRAINT program_actions_stage_check ON program_actions IS
    'A stage names its exercise and stage, and only a stage names them or a slot';

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
        programs_moved           INTEGER,
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
    _programs_moved  INTEGER;
    _programs        UUID[];
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

        -- Programs: a rule on the source moves to the target, and the target's
        -- own rule wins where a program has both, as with preferences. Bases move
        -- with their history; a source move from the same workout as a target
        -- move is the one dropped, since one workout moves a base once.
        WITH _moved AS (
            UPDATE programs
            SET rules = CASE
                    WHEN rules ? _target_id::text THEN rules - _source_id::text
                    ELSE (rules - _source_id::text) || jsonb_build_object(_target_id::text, rules -> _source_id::text)
                END,
                updated_at = now()
            WHERE user_id = _user_id
            AND rules ? _source_id::text
            RETURNING id
        )
        SELECT coalesce(array_agg(id), '{}')
        INTO _programs
        FROM _moved;

        WITH _dropped AS (
            DELETE FROM program_bases s
            WHERE s.user_id = _user_id
            AND s.exercise_id = _source_id
            AND s.workout_id IS NOT NULL
            AND EXISTS (
                SELECT 1
                FROM program_bases t
                WHERE t.program_id = s.program_id
                AND t.exercise_id = _target_id
                AND t.slot IS NOT DISTINCT FROM s.slot
                AND t.workout_id = s.workout_id
            )
            RETURNING program_id
        )
        SELECT _programs || coalesce(array_agg(program_id), '{}')
        INTO _programs
        FROM _dropped;

        WITH _moved AS (
            UPDATE program_bases
            SET exercise_id = _target_id
            WHERE user_id = _user_id
            AND exercise_id = _source_id
            RETURNING program_id
        )
        SELECT _programs || coalesce(array_agg(program_id), '{}')
        INTO _programs
        FROM _moved;

        -- A ladder's rungs name exercises too. The source becomes the target in
        -- place, and where the ladder already had the target, the first of the
        -- two stays; a ladder left with one rung has nowhere to climb and goes.
        WITH _moved AS (
            UPDATE programs p
            SET rules = (
                    SELECT coalesce(
                        jsonb_object_agg(r.key, CASE WHEN l.rungs IS NULL THEN r.value ELSE jsonb_set(r.value, '{rungs}', l.rungs) END)
                            FILTER (WHERE l.rungs IS NULL OR jsonb_array_length(l.rungs) >= 2),
                        '{}'
                    )
                    FROM jsonb_each(p.rules) r
                    LEFT JOIN LATERAL (
                        SELECT jsonb_agg(to_jsonb(rung) ORDER BY first) AS rungs
                        FROM (
                            SELECT CASE WHEN e.rung = _source_id::text THEN _target_id::text ELSE e.rung END AS rung,
                                min(e.at) AS first
                            FROM jsonb_array_elements_text(r.value -> 'rungs') WITH ORDINALITY e(rung, at)
                            GROUP BY 1
                        ) moved
                    ) l ON r.value -> 'rungs' ? _source_id::text
                ),
                updated_at = now()
            WHERE p.user_id = _user_id
            AND EXISTS (
                SELECT 1
                FROM jsonb_each(p.rules) r
                WHERE jsonb_typeof(r.value -> 'rungs') = 'array'
                AND r.value -> 'rungs' ? _source_id::text
            )
            RETURNING p.id
        )
        SELECT _programs || coalesce(array_agg(id), '{}')
        INTO _programs
        FROM _moved;

        -- and so does a set's share of another exercise's base
        UPDATE template_exercise_sets s
        SET target = jsonb_set(s.target, '{of}', to_jsonb(_target_id::text))
        FROM template_exercises te
        JOIN templates t ON t.id = te.template_id
        WHERE te.id = s.template_exercise_id
        AND t.user_id = _user_id
        AND s.target ->> 'of' = _source_id::text;

        -- a ladder's advances name both exercises
        WITH _moved AS (
            UPDATE program_actions
            SET from_exercise = CASE WHEN from_exercise = _source_id THEN _target_id ELSE from_exercise END,
                to_exercise = CASE WHEN to_exercise = _source_id THEN _target_id ELSE to_exercise END
            WHERE user_id = _user_id
            AND _source_id IN (from_exercise, to_exercise)
            RETURNING program_id
        )
        SELECT _programs || coalesce(array_agg(program_id), '{}')
        INTO _programs
        FROM _moved;

        -- and a stage names the exercise whose stage it moved
        WITH _moved AS (
            UPDATE program_actions
            SET exercise_id = _target_id
            WHERE user_id = _user_id
            AND exercise_id = _source_id
            RETURNING program_id
        )
        SELECT _programs || coalesce(array_agg(program_id), '{}')
        INTO _programs
        FROM _moved;

        _programs_moved := (SELECT count(DISTINCT id) FROM unnest(_programs) id);

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

    RETURN QUERY SELECT _we_moved, _te_moved, _pref_moved, _pref_dropped, _chart_moved, _goals_moved, _programs_moved, _deleted;
END
$$;

COMMENT ON FUNCTION _move_exercise_history(TEXT, UUID, UUID, BOOLEAN) IS
    'Re-keys one user''s workout exercises, template exercises, preferences, goals, and programs'' rules (ladder rungs included, a ladder left with one rung dropped), bases, ladder advances, stages and set targets'' share of another exercise from the source exercise to the target, then deletes the source if the user owns it; a dry run returns the same counts and writes nothing. Both exercises must be the library''s or the user''s own (no_data_found otherwise); source and target must differ (invalid_parameter_value); the target''s category must keep sets in the source''s columns, the four load-by-reps categories being interchangeable (datatype_mismatch otherwise). Where the user has a preference row on both, the target''s is kept and the source''s counted as dropped; where a program has a rule on both, the target''s is kept.';
