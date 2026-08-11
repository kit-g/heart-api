-- A short, user-authored note pinned to a workout exercise — e.g. "do one hand
-- at a time", "pause at the bottom". It is a description of how the exercise was
-- (or should be) performed, distinct from a `comment`: a comment is social,
-- threaded, and lives in its own table; a note is a single inline pin the owner
-- writes and edits as part of the workout itself.
--
-- Plain user text, not a measurement, so unlike `met`/`calories` the device-only
-- health rule does not touch it. Bounded to keep it a pin rather than an essay
-- (that is what comments are for) and to stop a pathological payload bloating
-- every workout read — the exercises blob is returned in full on every fetch.

ALTER TABLE workout_exercises
    ADD COLUMN IF NOT EXISTS note TEXT;

ALTER TABLE workout_exercises
    DROP CONSTRAINT IF EXISTS workout_exercises_note_length_check;
ALTER TABLE workout_exercises
    ADD CONSTRAINT workout_exercises_note_length_check
        CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500);

COMMENT ON COLUMN workout_exercises.note IS
    'Short user-authored pin describing how this exercise was performed (max 500 chars); NULL when the user left no note. Distinct from a comment.';

-- Surface the new column in the read shape. The archive snapshot
-- (archive.deleted_workouts.exercises) is built through this same function, so a
-- deleted workout keeps its notes with no extra plumbing.
DROP FUNCTION IF EXISTS _workout_exercises(_workout_id UUID);
CREATE OR REPLACE FUNCTION _workout_exercises(_workout_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT COALESCE(
  jsonb_agg(
    jsonb_build_object(
      'id', we.id,
      'exercise', jsonb_build_object(
          'id',       e.id,
          'category', e.category,
          'target',   e.target,
          'name',     e.name
      ),
      'exercise_order', we.exercise_order,
      'met',            we.met,
      'note',           we.note,
      'sets',           _exercise_sets(we.id)
    ) ORDER BY we.exercise_order
  ) FILTER (WHERE we.id IS NOT NULL),
  '[]'::JSONB
)
FROM workout_exercises we
LEFT JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = _workout_id
$$;
