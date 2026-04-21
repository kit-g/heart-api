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
SELECT 
  id, 
  name, 
  started_at, 
  completed_at, 
  created_at, 
  _workout_exercises(id) AS exercises
FROM workouts
WHERE user_id = @userId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

final _getWorkout = '''
SELECT 
  id, 
  name, 
  started_at, 
  completed_at, 
  created_at, 
  _workout_exercises(id) AS exercises
FROM workouts
WHERE id = @workoutId::uuid AND user_id = @userId
''';

final _saveWorkout = '''
WITH
_order_to_name AS (
  SELECT 
    (ex->>'order')::int AS exercise_order, 
    ex->>'exercise_name' AS exercise_name
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  SELECT DISTINCT ON (e.name) e.id AS exercise_id, e.name
  FROM exercises e
  JOIN _order_to_name otn ON otn.exercise_name = e.name
  WHERE e.user_id IS NULL OR e.user_id = @userId
  ORDER BY e.name, e.user_id NULLS LAST
),
_workout AS (
  INSERT INTO workouts (user_id, name, started_at, completed_at)
  VALUES (@userId, @name, @startedAt, @completedAt)
  RETURNING id, name, started_at, completed_at, created_at
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order)
  SELECT w.id, el.exercise_id, otn.exercise_order
  FROM _workout w
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  RETURNING id, exercise_order
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s                   AS set_data,
    (t.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY t(s, ordinality)
),
_inserted_sets AS (
  INSERT INTO exercise_sets (workout_exercise_id, weight, reps, duration, distance, completed, started_at, set_order)
  SELECT
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    coalesce((si.set_data->>'completed')::boolean, false),
    (si.set_data->>'started_at')::timestamptz,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, set_order
),
_sets_json AS (
  SELECT
    workout_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 
        'weight', weight, 
        'reps', reps, 
        'duration', duration,
        'distance', distance, 
        'completed', completed, 
        'started_at', started_at,
        'set_order', set_order
      ) ORDER BY set_order
    ) AS sets_json
  FROM _inserted_sets
  GROUP BY workout_exercise_id
),
_exercises_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ie.id,
      'exercise', jsonb_build_object(
        'id', el.exercise_id, 
        'category', e.category, 
        'target', e.target, 
        'name', el.name
      ),
      'exercise_order', ie.exercise_order,
      'sets', COALESCE(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _order_to_name otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT 
  w.id, 
  w.name,
  w.started_at, 
  w.completed_at, 
  w.created_at,
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises
FROM _workout w
LEFT JOIN _exercises_json ej 
  ON true
''';

final _replaceWorkout = '''
WITH
_order_to_name AS (
  SELECT 
    (ex->>'order')::int AS exercise_order, 
    ex->>'exercise_name' AS exercise_name
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  SELECT DISTINCT ON (e.name) e.id AS exercise_id, e.name
  FROM exercises e
  JOIN _order_to_name otn ON otn.exercise_name = e.name
  WHERE e.user_id IS NULL OR e.user_id = @userId
  ORDER BY e.name, e.user_id NULLS LAST
),
_workout AS (
  UPDATE workouts
  SET name = @name, started_at = @startedAt, completed_at = @completedAt
  WHERE id = @workoutId::uuid AND user_id = @userId
  RETURNING id, name, started_at, completed_at, created_at
),
_deleted AS (
  DELETE FROM workout_exercises
  WHERE workout_id = (SELECT id FROM _workout)
  RETURNING id
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order)
  SELECT 
    w.id, 
    el.exercise_id, 
    otn.exercise_order
  FROM _workout w
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  WHERE NOT exists(SELECT 1 FROM _deleted WHERE false)
  RETURNING id, exercise_order
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s AS set_data,
    (t.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY t(s, ordinality)
),
_inserted_sets AS (
  INSERT INTO exercise_sets (workout_exercise_id, weight, reps, duration, distance, completed, started_at, set_order)
  SELECT
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    COALESCE((si.set_data->>'completed')::boolean, false),
    (si.set_data->>'started_at')::timestamptz,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, set_order
),
_sets_json AS (
  SELECT
    workout_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 
        'weight', weight, 
        'reps', reps, 
        'duration', duration,
        'distance', distance, 
        'completed', completed, 
        'started_at', started_at,
        'set_order', set_order
      ) ORDER BY set_order
    ) AS sets_json
  FROM _inserted_sets
  GROUP BY workout_exercise_id
),
_exercises_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ie.id,
      'exercise', jsonb_build_object(
        'id', el.exercise_id, 
        'category', e.category, 
        'target', e.target, 
        'name', el.name
      ),
      'exercise_order', ie.exercise_order,
      'sets', coalesce(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _order_to_name otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT w.id, w.name, w.started_at, w.completed_at, w.created_at,
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises
FROM _workout w
LEFT JOIN _exercises_json ej ON true
''';

final _deleteWorkout = '''
DELETE FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId
''';
