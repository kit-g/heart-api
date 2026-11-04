part of '../db.dart';

/// Inserts from a visibility check rather than from the literal id, because the
/// foreign key alone is the wrong gate twice over: it proves only that the
/// exercise *exists*, so a plain `VALUES` insert accepts another account's
/// private custom (heart-api#74), and an id that exists nowhere raises a raw
/// `23503` the caller sees as a 500.
///
/// The `SELECT` applies the same predicate every other exercise read uses — the
/// caller's own customs plus the shared library. An id that is neither matches
/// no row, inserts nothing, and returns nothing, which the db layer turns into
/// `404 unknown_exercise`. Absent and not-yours are deliberately the same
/// answer: distinguishing them would confirm that someone else's exercise is
/// real.
///
/// `RETURNING` is the merged row, not the request: a write of one field
/// `COALESCE`s the other, so the stored preference can differ from what was
/// sent, and the caller should be told what it actually holds.
const _saveExercisePreference = '''
INSERT INTO exercise_preferences (user_id, exercise_id, unit_system, rest_timer, note)
SELECT @userId, e.id, @unitSystem::text, @restTimer::integer, @note::text
FROM exercises e
WHERE e.id = @exerciseId::uuid
  AND (e.user_id IS NULL OR e.user_id = @userId)
ON CONFLICT (user_id, exercise_id)
DO UPDATE SET
  unit_system = COALESCE(EXCLUDED.unit_system, exercise_preferences.unit_system),
  rest_timer  = COALESCE(EXCLUDED.rest_timer, exercise_preferences.rest_timer),
  -- null means "leave it", same as its siblings; unpinning is _clearExerciseNote
  note        = COALESCE(EXCLUDED.note, exercise_preferences.note)
RETURNING exercise_id, unit_system, rest_timer, note
''';

const _clearUnitPreference = '''
UPDATE exercise_preferences
SET unit_system = NULL
WHERE exercise_id = @id::uuid
  AND user_id = @userId
''';

const _clearRestTimer = '''
UPDATE exercise_preferences
SET rest_timer = NULL
WHERE exercise_id = @id::uuid
  AND user_id = @userId
''';

/// Cancels a pinned note. The row itself stays — it may still carry a unit or a
/// rest timer — and every note already copied onto a logged workout is
/// untouched: those record how the exercise was actually done that day.
const _clearExerciseNote = '''
UPDATE exercise_preferences
SET note = NULL
WHERE exercise_id = @id::uuid
  AND user_id = @userId
''';

/// Unpaginated, same as `_getChartPreferences` — `UNIQUE (user_id, exercise_id)`
/// bounds this to a handful of rows per user. Excludes chart-only rows (those
/// belong to `GET /charts`); ordered by `exercise_id` for a stable response.
const _listExercisePreferences = '''
SELECT exercise_id, unit_system, rest_timer, note
FROM exercise_preferences
WHERE user_id = @userId
  AND (unit_system IS NOT NULL OR rest_timer IS NOT NULL OR note IS NOT NULL)
ORDER BY exercise_id
''';
