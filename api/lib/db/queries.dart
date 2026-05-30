part of 'db.dart';

extension on String {
  Sql toSql() => Sql.named(this);
}

final _listGallery = '''
SELECT id, workout_id, key
FROM workout_images
WHERE user_id = @userId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

final _insertImage = '''
INSERT INTO workout_images (workout_id, user_id, key)
VALUES (@workoutId::uuid, @userId, @key)
RETURNING id, workout_id, key
''';

final _deleteImage = '''
DELETE FROM workout_images
WHERE key = @key AND user_id = @userId AND workout_id = @workoutId::uuid
RETURNING id
''';

final _getUserImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId
''';

final _getWorkoutImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId 
  AND workout_id = @workoutId::uuid
''';

final _updateAccount = '''
INSERT INTO profiles (id, email, username, avatar_url, updated_at)
VALUES (@id, @email, @username, @avatar, now())
ON CONFLICT (id)
DO UPDATE
SET
username = EXCLUDED.username,
email = EXCLUDED.email,
avatar_url = EXCLUDED.avatar_url,
updated_at = now()
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at
''';

final _scheduleAccountDeletion = '''
UPDATE profiles
SET 
  account_deletion_schedule = coalesce(@schedule, account_deletion_schedule), 
  scheduled_for_deletion_at = coalesce(@scheduledAt, scheduled_for_deletion_at)
WHERE id = @userId
''';

final _updateAvatarUrl = '''
UPDATE profiles
SET 
  avatar_url = @avatarUrl, 
  updated_at = now()
WHERE id = @userId
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at
''';

final _undoAccountDeletion = '''
UPDATE profiles
SET
  account_deletion_schedule = NULL,
  scheduled_for_deletion_at = NULL
WHERE id = @userId
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at
''';

final _deleteAccount = '''
DELETE FROM profiles
WHERE id = @userId
''';

final _listExercises = '''
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', e.id,
      'name', COALESCE(t.name, e.name),
      'category', e.category,
      'target', e.target,
      'instructions', COALESCE(t.instructions, e.instructions),
      'asset', e.asset,
      'thumbnail', e.thumbnail,
      'muscles', e.muscles,
      'own', e.user_id IS NOT NULL,
      'archived', e.archived
    ) ORDER BY e.name
  ),
  '[]'::jsonb
) AS exercises
FROM exercises e
LEFT JOIN exercise_translations t ON t.exercise_id = e.id AND t.locale = @locale
WHERE
  CASE WHEN @owned::boolean
    THEN e.user_id = @userId
    ELSE e.user_id IS NULL OR e.user_id = @userId
  END
''';

final _createExercise = '''
INSERT INTO exercises (
  name, 
  category, 
  target, 
  instructions, 
  user_id
) VALUES (
  @name, 
  @category, 
  @target, 
  @instructions, 
  @userId
)
RETURNING id, name, category, target, instructions, asset, thumbnail, muscles, archived,
          user_id IS NOT NULL AS own
''';

final _updateExercise = '''
UPDATE exercises
SET
  category = coalesce(@category, category),
  target = coalesce(@target, target),
  instructions = coalesce(@instructions, instructions),
  archived = coalesce(@archived, archived)
WHERE id = @exerciseId::uuid 
  AND user_id = @userId
RETURNING id, name, category, target, instructions, asset, thumbnail, muscles, archived,
          user_id IS NOT NULL AS own
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
WITH
_auth AS (
  SELECT (
    @requesterId::text = @targetUserId::text
    OR EXISTS (
      SELECT 1 FROM connections
      WHERE (initiator_id = @requesterId AND target_id = @targetUserId AND initiator_role IN ('COACH', 'PEER'))
         OR (initiator_id = @targetUserId AND target_id = @requesterId AND target_role IN ('COACH', 'PEER'))
    )
  ) AS allowed
),
_workouts AS (
  SELECT
    id, name, started_at, completed_at, created_at,
    _workout_exercises(id) AS exercises,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
       FROM workout_images wi WHERE wi.workout_id = workouts.id),
      '[]'::jsonb
    ) AS images
  FROM workouts
  WHERE (SELECT allowed FROM _auth)
    AND user_id = @targetUserId::text
    AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
  ORDER BY id DESC
  LIMIT @limit
)
SELECT id, name, started_at, completed_at, created_at, exercises, images, false AS forbidden FROM _workouts
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _auth WHERE NOT allowed
''';

final _getWorkout = '''
SELECT
  w.id,
  w.name,
  w.started_at,
  w.completed_at,
  w.created_at,
  _workout_exercises(w.id) AS exercises,
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) AS images
FROM workouts w
WHERE w.id = @workoutId::uuid AND w.user_id = @userId
''';

final _getTargetWorkout = '''
WITH
_auth AS (
  SELECT (
    @requesterId::text = @targetUserId::text
    OR EXISTS (
      SELECT 1 FROM connections
      WHERE (initiator_id = @requesterId AND target_id = @targetUserId AND initiator_role IN ('COACH', 'PEER'))
         OR (initiator_id = @targetUserId AND target_id = @requesterId AND target_role IN ('COACH', 'PEER'))
    )
  ) AS allowed
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.created_at,
  _workout_exercises(w.id) AS exercises,
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) AS images,
  false AS forbidden
FROM workouts w
WHERE w.id = @workoutId::uuid AND w.user_id = @targetUserId::text AND (SELECT allowed FROM _auth)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _auth WHERE NOT allowed
''';

final _saveWorkout = '''
WITH
_order_to_name AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    ex->>'exercise_name' AS exercise_name,
    ex->>'unit_system' AS unit_system
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
  INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order, unit_system)
  SELECT w.id, el.exercise_id, otn.exercise_order, otn.unit_system
  FROM _workout w
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  RETURNING id, exercise_order, unit_system
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
      'unit_system', ie.unit_system,
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
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises,
  '[]'::jsonb AS images
FROM _workout w
LEFT JOIN _exercises_json ej
  ON true
''';

final _replaceWorkout = '''
WITH
_order_to_name AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    ex->>'exercise_name' AS exercise_name,
    ex->>'unit_system' AS unit_system
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
  INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order, unit_system)
  SELECT
    w.id,
    el.exercise_id,
    otn.exercise_order,
    otn.unit_system
  FROM _workout w
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  WHERE NOT exists(SELECT 1 FROM _deleted WHERE false)
  RETURNING id, exercise_order, unit_system
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
      'unit_system', ie.unit_system,
      'sets', coalesce(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _order_to_name otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.created_at,
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises,
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) AS images
FROM _workout w
LEFT JOIN _exercises_json ej ON true
''';

final _deleteWorkout = '''
DELETE FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId
''';

final _saveTemplate = '''
WITH
_order_to_name AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    ex->>'exercise_name' AS exercise_name,
    ex->>'unit_system' AS unit_system
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  SELECT DISTINCT ON (e.name) e.id, e.name, e.category, e.target
  FROM exercises e
  JOIN _order_to_name otn ON otn.exercise_name = e.name
  WHERE e.user_id IS NULL OR e.user_id = @userId
  ORDER BY e.name, e.user_id NULLS LAST
),
_template AS (
  INSERT INTO templates (user_id, name, order_index)
  VALUES (@userId, @name, @orderIndex)
  RETURNING id, name, order_index, source_template_id, assigned_by, sync_enabled, created_at
),
_inserted_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order, unit_system)
  SELECT t.id, el.id, otn.exercise_order, otn.unit_system
  FROM _template t
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  RETURNING id, exercise_id, exercise_order, unit_system
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s AS set_data,
    (ord.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY ord(s, ordinality)
),
_inserted_sets AS (
  INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, duration, distance, set_order)
  SELECT
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, template_exercise_id, weight, reps, duration, distance, set_order
),
_sets_json AS (
  SELECT
    template_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 'weight', weight, 'reps', reps,
        'duration', duration, 'distance', distance, 'set_order', set_order
      ) ORDER BY set_order
    ) AS sets_json
  FROM _inserted_sets
  GROUP BY template_exercise_id
),
_exercises_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ie.id,
      'exercise', jsonb_build_object('id', el.id, 'name', el.name, 'category', el.category, 'target', el.target),
      'exercise_order', ie.exercise_order,
      'unit_system', ie.unit_system,
      'sets', COALESCE(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _exercise_lookup el ON el.id = ie.exercise_id
  LEFT JOIN _sets_json sj ON sj.template_exercise_id = ie.id
)
SELECT
  t.id,
  t.name,
  t.order_index,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  COALESCE(ej.exercises_json, '[]'::jsonb) AS exercises
FROM _template t
LEFT JOIN profiles p ON p.id = t.assigned_by
LEFT JOIN _exercises_json ej ON true
''';

final _replaceTemplate = '''
WITH
_order_to_name AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    ex->>'exercise_name' AS exercise_name,
    ex->>'unit_system' AS unit_system
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  SELECT DISTINCT ON (e.name) e.id, e.name, e.category, e.target
  FROM exercises e
  JOIN _order_to_name otn ON otn.exercise_name = e.name
  WHERE e.user_id IS NULL OR e.user_id = @userId
  ORDER BY e.name, e.user_id NULLS LAST
),
_template AS (
  UPDATE templates
  SET name = @name, order_index = @orderIndex
  WHERE id = @templateId::uuid AND user_id = @userId
  RETURNING id, name, order_index, source_template_id, assigned_by, sync_enabled, created_at
),
_deleted AS (
  DELETE FROM template_exercises WHERE template_id = (SELECT id FROM _template)
  RETURNING id
),
_inserted_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order, unit_system)
  SELECT t.id, el.id, otn.exercise_order, otn.unit_system
  FROM _template t
  CROSS JOIN _order_to_name otn
  JOIN _exercise_lookup el ON el.name = otn.exercise_name
  WHERE NOT EXISTS (SELECT 1 FROM _deleted WHERE false)
  RETURNING id, exercise_id, exercise_order, unit_system
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s AS set_data,
    (ord.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY ord(s, ordinality)
),
_inserted_sets AS (
  INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, duration, distance, set_order)
  SELECT
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, template_exercise_id, weight, reps, duration, distance, set_order
),
_sets_json AS (
  SELECT
    template_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 'weight', weight, 'reps', reps,
        'duration', duration, 'distance', distance, 'set_order', set_order
      ) ORDER BY set_order
    ) AS sets_json
  FROM _inserted_sets
  GROUP BY template_exercise_id
),
_exercises_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ie.id,
      'exercise', jsonb_build_object('id', el.id, 'name', el.name, 'category', el.category, 'target', el.target),
      'exercise_order', ie.exercise_order,
      'unit_system', ie.unit_system,
      'sets', COALESCE(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _exercise_lookup el ON el.id = ie.exercise_id
  LEFT JOIN _sets_json sj ON sj.template_exercise_id = ie.id
)
SELECT
  t.id,
  t.name,
  t.order_index,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  COALESCE(ej.exercises_json, '[]'::jsonb) AS exercises
FROM _template t
LEFT JOIN profiles p ON p.id = t.assigned_by
LEFT JOIN _exercises_json ej ON true
''';

final _getTemplate = '''
SELECT
  t.id,
  t.name,
  t.order_index,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  _template_exercises(t.id) AS exercises
FROM templates t
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.id = @templateId::uuid AND t.user_id = @userId
''';

final _listTemplates = '''
SELECT
  t.id,
  t.name,
  t.order_index,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  _template_exercises(t.id) AS exercises
FROM templates t
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.user_id = @userId
  AND (@cursor::uuid IS NULL OR t.id < @cursor::uuid)
ORDER BY t.id DESC
LIMIT @limit
''';

final _listTemplateShares = '''
SELECT
  ts.id AS share_uuid,
  ts.student_id,
  ts.master_template_id,
  ts.student_template_id,
  t.name AS template_name,
  p.username AS student_username,
  p.avatar_url AS student_avatar,
  ts.created_at
FROM template_shares ts
JOIN templates t ON t.id = ts.master_template_id
JOIN profiles p ON p.id = ts.student_id
WHERE ts.coach_id = @userId
  AND (@cursor::uuid IS NULL OR ts.id < @cursor::uuid)
ORDER BY ts.id DESC
LIMIT @limit
''';

final _shareTemplate = '''
WITH
_student AS (
  SELECT id, username, avatar_url FROM profiles WHERE id = @studentId
),
_master AS (
  SELECT id, name FROM templates WHERE id = @masterTemplateId::uuid AND user_id = @coachId
),
_existing AS (
  SELECT student_template_id, created_at FROM template_shares
  WHERE coach_id = @coachId AND student_id = @studentId AND master_template_id = @masterTemplateId::uuid
),
_allowed AS (
  SELECT 1 FROM connections
  WHERE (initiator_id = @coachId AND target_id = @studentId AND initiator_role IN ('COACH', 'PEER'))
     OR (initiator_id = @studentId AND target_id = @coachId AND target_role IN ('COACH', 'PEER'))
  LIMIT 1
),
_should_share AS (
  SELECT 1
  WHERE EXISTS (SELECT 1 FROM _master)
    AND EXISTS (SELECT 1 FROM _allowed)
    AND NOT EXISTS (SELECT 1 FROM _existing)
),
-- For each exercise the master template references, capture its full data
-- and look up whichever exercise the student already has access to under
-- the same name (their own custom first, otherwise the global).
_master_exercises AS (
  SELECT
    te.id AS source_te_id,
    te.exercise_order,
    e.name, e.category, e.target, e.instructions, e.asset, e.thumbnail, e.muscles,
    (
      SELECT e2.id FROM exercises e2
      WHERE e2.name = e.name
        AND (e2.user_id IS NULL OR e2.user_id = @studentId)
      ORDER BY e2.user_id NULLS LAST
      LIMIT 1
    ) AS resolved_id
  FROM template_exercises te
  JOIN exercises e ON e.id = te.exercise_id
  WHERE te.template_id = @masterTemplateId::uuid
    AND EXISTS (SELECT 1 FROM _should_share)
),
-- Copy any unresolved exercises into the student's library so the FK
-- holds. DISTINCT ON dedupes if the master happened to list the same
-- exercise twice.
_copied_exercises AS (
  INSERT INTO exercises (name, category, target, instructions, asset, thumbnail, muscles, user_id)
  SELECT DISTINCT ON (name)
    name, category, target, instructions, asset, thumbnail, muscles, @studentId
  FROM _master_exercises
  WHERE resolved_id IS NULL
  RETURNING id, name
),
-- Final mapping of exercise_order → exercise_id the student template
-- should reference.
_resolved_exercises AS (
  SELECT
    me.exercise_order,
    me.source_te_id,
    coalesce(me.resolved_id, c.id) AS exercise_id
  FROM _master_exercises me
  LEFT JOIN _copied_exercises c ON c.name = me.name AND me.resolved_id IS NULL
),
_new_template AS (
  INSERT INTO templates (user_id, name, order_index, source_template_id, assigned_by, sync_enabled)
  SELECT @studentId, m.name, 0, m.id, @coachId, true
  FROM _master m
  WHERE EXISTS (SELECT 1 FROM _should_share)
  RETURNING id
),
_new_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order)
  SELECT nt.id, re.exercise_id, re.exercise_order
  FROM _new_template nt
  CROSS JOIN _resolved_exercises re
  RETURNING id, exercise_order
),
_new_sets AS (
  INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, duration, distance, set_order)
  SELECT ne.id, tes.weight, tes.reps, tes.duration, tes.distance, tes.set_order
  FROM _new_exercises ne
  JOIN _resolved_exercises re ON re.exercise_order = ne.exercise_order
  JOIN template_exercise_sets tes ON tes.template_exercise_id = re.source_te_id
  RETURNING id
),
_new_share AS (
  INSERT INTO template_shares (coach_id, student_id, master_template_id, student_template_id)
  SELECT @coachId, @studentId, @masterTemplateId::uuid, nt.id
  FROM _new_template nt
  WHERE NOT EXISTS (SELECT 1 FROM _new_sets WHERE false)
  RETURNING student_template_id, created_at
)
SELECT
  s.id AS student_id,
  @masterTemplateId::uuid AS master_template_id,
  COALESCE(ns.student_template_id, ex.student_template_id) AS student_template_id,
  m.name AS template_name,
  s.username AS student_username,
  s.avatar_url AS student_avatar,
  COALESCE(ns.created_at, ex.created_at) AS created_at,
  NOT EXISTS (SELECT 1 FROM _allowed) AND NOT EXISTS (SELECT 1 FROM _existing) AS forbidden
FROM _student s
CROSS JOIN _master m
LEFT JOIN _new_share ns ON true
LEFT JOIN _existing ex ON true
''';

final _deleteTemplate = '''
WITH
_student_templates AS (
  SELECT student_template_id FROM template_shares
  WHERE coach_id = @coachId AND master_template_id = @templateId::uuid
),
_deleted_students AS (
  DELETE FROM templates WHERE id IN (SELECT student_template_id FROM _student_templates)
  RETURNING id
),
_deleted_master AS (
  DELETE FROM templates
  WHERE id = @templateId::uuid AND user_id = @coachId
    AND NOT EXISTS (SELECT 1 FROM _deleted_students WHERE false)
  RETURNING id
)
SELECT id FROM _deleted_master
''';

final _deleteShare = '''
WITH
_deleted AS (
  DELETE FROM templates
  WHERE id = (
    SELECT student_template_id FROM template_shares
    WHERE coach_id = @coachId AND student_id = @studentId AND master_template_id = @masterTemplateId::uuid
  )
  RETURNING id
)
SELECT id FROM _deleted
''';

final _areConnected = '''
SELECT 1 FROM connections
WHERE status = 'active'
  AND (
    (initiator_id = @userA AND target_id = @userB)
    OR
    (initiator_id = @userB AND target_id = @userA)
  )
LIMIT 1
''';

final _resolveCommentTargetOwner = '''
SELECT user_id FROM workouts
WHERE id = (CASE @targetType
  WHEN 'workout' THEN @targetId::uuid
  WHEN 'workout_exercise' THEN (SELECT workout_id FROM workout_exercises WHERE id = @targetId::uuid)
  WHEN 'exercise_set' THEN (
    SELECT we.workout_id FROM workout_exercises we
    JOIN exercise_sets es ON es.workout_exercise_id = we.id
    WHERE es.id = @targetId::uuid
  )
  WHEN 'workout_image' THEN (SELECT workout_id FROM workout_images WHERE id = @targetId::uuid)
END)
''';

final _insertComment = '''
INSERT INTO comments (author_id, body, workout_id, workout_exercise_id, exercise_set_id, workout_image_id)
VALUES (
  @authorId,
  @body,
  CASE WHEN @targetType = 'workout' THEN @targetId::uuid END,
  CASE WHEN @targetType = 'workout_exercise' THEN @targetId::uuid END,
  CASE WHEN @targetType = 'exercise_set' THEN @targetId::uuid END,
  CASE WHEN @targetType = 'workout_image' THEN @targetId::uuid END
)
RETURNING
  id,
  author_id,
  body,
  created_at,
  edited_at,
  COALESCE(workout_id, workout_exercise_id, exercise_set_id, workout_image_id) AS target_id,
  CASE
    WHEN workout_id IS NOT NULL THEN 'workout'
    WHEN workout_exercise_id IS NOT NULL THEN 'workout_exercise'
    WHEN exercise_set_id IS NOT NULL THEN 'exercise_set'
    WHEN workout_image_id IS NOT NULL THEN 'workout_image'
  END AS target_type
''';

final _listComments = '''
SELECT
  id,
  author_id,
  body,
  created_at,
  edited_at,
  COALESCE(workout_id, workout_exercise_id, exercise_set_id, workout_image_id) AS target_id,
  CASE
    WHEN workout_id IS NOT NULL THEN 'workout'
    WHEN workout_exercise_id IS NOT NULL THEN 'workout_exercise'
    WHEN exercise_set_id IS NOT NULL THEN 'exercise_set'
    WHEN workout_image_id IS NOT NULL THEN 'workout_image'
  END AS target_type
FROM comments
WHERE
  CASE @targetType
    WHEN 'workout' THEN workout_id = @targetId::uuid
    WHEN 'workout_exercise' THEN workout_exercise_id = @targetId::uuid
    WHEN 'exercise_set' THEN exercise_set_id = @targetId::uuid
    WHEN 'workout_image' THEN workout_image_id = @targetId::uuid
  END
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

final _updateComment = '''
UPDATE comments
SET body = @body, edited_at = now()
WHERE id = @commentId::uuid AND author_id = @authorId
RETURNING
  id,
  author_id,
  body,
  created_at,
  edited_at,
  COALESCE(workout_id, workout_exercise_id, exercise_set_id, workout_image_id) AS target_id,
  CASE
    WHEN workout_id IS NOT NULL THEN 'workout'
    WHEN workout_exercise_id IS NOT NULL THEN 'workout_exercise'
    WHEN exercise_set_id IS NOT NULL THEN 'exercise_set'
    WHEN workout_image_id IS NOT NULL THEN 'workout_image'
  END AS target_type
''';

final _deleteComment = '''
DELETE FROM comments
WHERE id = @commentId::uuid AND author_id = @authorId
RETURNING id
''';

final _upsertDevice = '''
INSERT INTO device_tokens (profile_id, platform, token, locale, settings, last_seen_at)
VALUES (@profileId, @platform, @token, @locale, @settings::jsonb, now())
ON CONFLICT (token)
DO UPDATE SET
  profile_id   = EXCLUDED.profile_id,
  platform     = EXCLUDED.platform,
  locale       = EXCLUDED.locale,
  settings     = EXCLUDED.settings,
  last_seen_at = now()
''';

final _listDeviceTokensWithLocale = '''
SELECT token, locale FROM device_tokens WHERE profile_id = @profileId
''';

final _deleteDeviceToken = '''
DELETE FROM device_tokens WHERE token = @token
''';
