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
    AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
  ORDER BY id DESC
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
          'started_at', es.started_at,
          'completed_at', es.completed_at,
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
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', _we.exercise_id_pk,
        'exercise', jsonb_build_object(
            'id', exercises.id,
            'category', exercises.category,
            'target', exercises.target,
            'name', exercises.name
        ),
        'exercise_order', _we.exercise_order,
        'sets', _we.sets
      ) ORDER BY _we.exercise_order
    ) FILTER (WHERE _we.exercise_id_pk IS NOT NULL), '[]'::jsonb
  ) AS exercises
FROM _workouts _w
LEFT JOIN _workout_exercises _we ON _we.workout_id = _w.id
INNER JOIN exercises ON exercises.id = _we.exercise_id
GROUP BY _w.id, _w.name, _w.started_at, _w.completed_at, _w.created_at
ORDER BY _w.id DESC
''';