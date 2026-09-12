-- A note pinned to an exercise: one per (user, exercise), a standing instruction
-- rather than a record of one session — workout_exercises.note stays that.
-- Bounded at 200 so it fits the per-session column it may be copied into.
-- The column is never dropped on a re-run (user-authored, not reproducible), so
-- only the constraint is swapped.

ALTER TABLE exercise_preferences
    ADD COLUMN IF NOT EXISTS note TEXT;

ALTER TABLE exercise_preferences
    DROP CONSTRAINT IF EXISTS exercise_preferences_note_length_check;
ALTER TABLE exercise_preferences
    ADD CONSTRAINT exercise_preferences_note_length_check
        CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 200);

COMMENT ON COLUMN exercise_preferences.note IS
    'Note pinned to this exercise by this user (max 200 chars); NULL when nothing is pinned. Per-session notes are workout_exercises.note.';

COMMENT ON CONSTRAINT exercise_preferences_note_length_check ON exercise_preferences IS
    'A pin is a pin, not an essay: 1-200 chars, or NULL for nothing pinned.';
