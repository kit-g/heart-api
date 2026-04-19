part of 'db.dart';

extension on String {
  Sql toSql() => Sql.named(this);
}

final _updateProfile = '''
INSERT INTO profiles (id, email, username, avatar_url, updated_at)
VALUES (@id, @email, @username, @avatar, now())
ON CONFLICT (id) 
DO UPDATE 
SET 
username = EXCLUDED.username, 
email = EXCLUDED.email, 
avatar_url = EXCLUDED.avatar_url, 
updated_at = now();
''';

final _createConnection = '''
WITH target_exists AS (
  SELECT 1 FROM profiles WHERE id = @targetId
),
inserted AS (
  INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain)
  SELECT @initiatorId, @targetId, @initiatorRole, @targetRole, @domain
  WHERE exists(SELECT 1 FROM target_exists)
  ON CONFLICT (initiator_id, target_id, domain) DO NOTHING
  RETURNING target_id, initiator_role AS "role", domain, status, created_at
)
SELECT target_id, "role", domain, status, created_at FROM inserted
UNION ALL
SELECT
  CASE WHEN initiator_id = @initiatorId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @initiatorId THEN initiator_role ELSE target_role END AS role,
  domain, 
  status, 
  created_at
FROM connections
WHERE domain = @domain
  AND exists(SELECT 1 FROM target_exists)
  AND NOT exists(SELECT 1 FROM inserted)
  AND (
    (initiator_id = @initiatorId AND target_id = @targetId)
    OR 
    (initiator_id = @targetId AND target_id = @initiatorId)
  )
''';

final _listConnections = '''
SELECT
  target_id,
  initiator_role AS role,
  domain,
  status,
  created_at
FROM connections
WHERE initiator_id = @userId
  AND (@role::text IS NULL OR initiator_role = @role)
UNION ALL
SELECT initiator_id AS target_id, target_role AS role, domain, status, created_at
FROM connections
WHERE target_id = @userId
  AND (@role::text IS NULL OR target_role = @role)
ORDER BY created_at DESC
''';

final _getConnection = '''
SELECT
  CASE WHEN initiator_id = @userId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @userId THEN initiator_role ELSE target_role END AS role,
  domain, status, created_at
FROM connections
WHERE domain = @domain
  AND (
    (initiator_id = @userId AND target_id = @targetId AND initiator_role = @role)
    OR (initiator_id = @targetId AND target_id = @userId AND target_role = @role)
  )
''';

final _deleteConnection = '''
DELETE FROM connections
WHERE (initiator_id, target_id, domain) IN (
  (@initiatorId, @targetId, @domain),
  (@targetId, @initiatorId, @domain)
)
''';

final _updateConnectionStatus = '''
UPDATE connections SET status = @newStatus
WHERE (initiator_id, target_id, domain) IN (
  (@initiatorId, @targetId, @domain),
  (@targetId, @initiatorId, @domain)
)
''';

final _listWorkouts = '''
WITH _workouts AS (
  SELECT id, name, started_at, completed_at, created_at
  FROM workouts
  WHERE user_id = @userId
    AND (@cursor::timestamptz IS NULL OR created_at < @cursor::timestamptz)
  ORDER BY created_at DESC
  LIMIT @limit
),
_workout_exercises AS (
  SELECT
    we.workout_id,
    we.id AS exercise_id_pk,
    we.exercise_id,
    we.exercise_order,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', es.id,
          'weight', es.weight,
          'reps', es.reps,
          'duration', es.duration,
          'distance', es.distance,
          'completed', es.completed,
          'set_order', es.set_order
        ) ORDER BY es.set_order
      ) FILTER (WHERE es.id IS NOT NULL), '[]'::jsonb
    ) AS sets
  FROM _workouts
  JOIN workout_exercises we ON we.workout_id = _workouts.id
  LEFT JOIN exercise_sets es ON es.workout_exercise_id = we.id
  GROUP BY we.workout_id, we.id, we.exercise_id, we.exercise_order
)
SELECT
  _w.id,
  _w.name,
  _w.started_at,
  _w.completed_at,
  _w.created_at,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', wea.exercise_id_pk,
        'exercise_id', wea.exercise_id,
        'exercise_order', wea.exercise_order,
        'sets', wea.sets
      ) ORDER BY wea.exercise_order
    ) FILTER (WHERE wea.exercise_id_pk IS NOT NULL), '[]'::jsonb
  ) AS exercises
FROM _workouts _w
LEFT JOIN _workout_exercises wea ON wea.workout_id = _w.id
GROUP BY _w.id, _w.name, _w.started_at, _w.completed_at, _w.created_at
ORDER BY _w.created_at DESC
''';