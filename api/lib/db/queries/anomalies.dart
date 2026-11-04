part of '../db.dart';

const _anomalyColumns = '''
  a.id, a.workout_id, COALESCE(w.started_at, w.created_at) AS workout_start, a.set_id,
  we.exercise_id, e.name AS exercise_name, a.reason, a.observed, a.typical, a.status, a.detected_at, a.resolved_at
''';

const _anomalyJoins = '''
JOIN workouts w ON w.id = a.workout_id
LEFT JOIN exercise_sets s ON s.id = a.set_id
LEFT JOIN workout_exercises we ON we.id = s.workout_exercise_id
LEFT JOIN exercises e ON e.id = we.exercise_id
''';

// Newest found first, so one raised again by an edit comes back to the top.
// The cursor is the last one's id, keyed on its place in that order.
const _getAnomalies =
    '''
WITH _after AS (
  SELECT detected_at, id
  FROM anomalies
  WHERE id = @cursor::uuid
    AND user_id = @userId
)
SELECT $_anomalyColumns
FROM anomalies a
$_anomalyJoins
WHERE a.user_id = @userId
  AND (@status::text IS NULL OR a.status = @status::text)
  AND (@cursor::uuid IS NULL OR (a.detected_at, a.id) < (SELECT detected_at, id FROM _after))
ORDER BY a.detected_at DESC, a.id DESC
LIMIT @limit
''';

// The pending ones whose workout started in the window: what an aggregate of
// that window was folded from without anyone having looked at them.
const _getPendingAnomalies =
    '''
SELECT $_anomalyColumns
FROM anomalies a
$_anomalyJoins
WHERE a.user_id = @userId
  AND a.status = 'pending'
  AND (@from::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) >= @from::timestamptz)
  AND (@to::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) < @to::timestamptz)
ORDER BY COALESCE(w.started_at, w.created_at), a.id
''';

// A decision may be changed; deciding the same again keeps when it was made.
const _resolveAnomaly =
    '''
WITH _resolved AS (
  UPDATE anomalies
  SET status      = @status,
      resolved_at = CASE WHEN status = @status THEN resolved_at ELSE now() END
  WHERE id = @anomalyId::uuid
    AND user_id = @userId
  RETURNING *
)
SELECT $_anomalyColumns
FROM _resolved a
$_anomalyJoins
''';
