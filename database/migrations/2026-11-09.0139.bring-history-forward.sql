-- Moves one account's training history forward by whole weeks, so that its latest
-- workout falls within the past seven days. Whole weeks keep every session on its
-- weekday, and moving everything by the same span keeps the history's shape: what
-- was a week apart stays a week apart. For a demo account whose log was entered once.

CREATE OR REPLACE FUNCTION _bring_history_forward(_user_id TEXT) RETURNS INTEGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    _weeks INTEGER;
    _by    INTERVAL;
BEGIN
    SELECT (current_date - max(started_at)::date) / 7
    INTO _weeks
    FROM workouts
    WHERE user_id = _user_id;

    IF coalesce(_weeks, 0) <= 0 THEN
        RETURN 0;
    END IF;

    _by := make_interval(weeks => _weeks);

    UPDATE workouts
    SET started_at = started_at + _by,
        completed_at = completed_at + _by,
        created_at = created_at + _by,
        hidden_at = hidden_at + _by,
        pauses = coalesce(
            (
                SELECT jsonb_agg(
                    p || jsonb_build_object(
                        'start', (p ->> 'start')::timestamptz + _by,
                        'end', (p ->> 'end')::timestamptz + _by
                    )
                    ORDER BY i
                )
                FROM jsonb_array_elements(pauses) WITH ORDINALITY AS t(p, i)
            ),
            '[]'::jsonb
        )
    WHERE user_id = _user_id;

    UPDATE exercise_sets s
    SET started_at = s.started_at + _by,
        completed_at = s.completed_at + _by
    FROM workout_exercises we
    JOIN workouts w ON w.id = we.workout_id
    WHERE we.id = s.workout_exercise_id
      AND w.user_id = _user_id;

    UPDATE skips
    SET at = at + _by
    WHERE user_id = _user_id;

    UPDATE program_actions
    SET at = at + _by
    WHERE user_id = _user_id;

    UPDATE program_bases
    SET at = at + _by
    WHERE user_id = _user_id;

    UPDATE goals g
    SET stages = (
        SELECT jsonb_agg(
            stage
                || CASE
                       WHEN stage ? 'dueOn'
                           THEN jsonb_build_object('dueOn', to_char((stage ->> 'dueOn')::date + _weeks * 7, 'YYYY-MM-DD'))
                       ELSE '{}'::jsonb
                   END
                || CASE
                       WHEN stage ? 'achievedAt'
                           THEN jsonb_build_object('achievedAt', (stage ->> 'achievedAt')::timestamptz + _by)
                       ELSE '{}'::jsonb
                   END
            ORDER BY i
        )
        FROM jsonb_array_elements(g.stages) WITH ORDINALITY AS t(stage, i)
    )
    WHERE g.user_id = _user_id;

    RETURN _weeks;
END
$$;

COMMENT ON FUNCTION _bring_history_forward(TEXT) IS
    'Moves an account''s workouts, sets, pauses, skips, program steps and goal dates forward by whole weeks until its latest workout is within the past seven days; returns the weeks moved';
