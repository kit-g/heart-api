part of 'db.dart';

extension on String {
  Sql toSql() => Sql.named(this);
}

const _listGallery = '''
SELECT id, workout_id, key
FROM workout_images
WHERE user_id = @userId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _insertImage = '''
INSERT INTO workout_images (workout_id, user_id, key)
VALUES (@workoutId::uuid, @userId, @key)
RETURNING id, workout_id, key
''';

const _deleteImage = '''
DELETE FROM workout_images
WHERE key = @key AND user_id = @userId AND workout_id = @workoutId::uuid
RETURNING id
''';

const _getUserImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId
''';

const _getWorkoutImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId 
  AND workout_id = @workoutId::uuid
''';

const _updateAccount = '''
INSERT INTO profiles (id, email, username, avatar_url, settings, updated_at)
VALUES (@id, @email, @username, @avatar, @settings::jsonb, now())
ON CONFLICT (id)
DO UPDATE
SET
username = EXCLUDED.username,
email = EXCLUDED.email,
avatar_url = EXCLUDED.avatar_url,
settings = EXCLUDED.settings,
updated_at = now()
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at, settings
''';

const _scheduleAccountDeletion = '''
UPDATE profiles
SET 
  account_deletion_schedule = coalesce(@schedule, account_deletion_schedule), 
  scheduled_for_deletion_at = coalesce(@scheduledAt, scheduled_for_deletion_at)
WHERE id = @userId
''';

const _updateAvatarUrl = '''
UPDATE profiles
SET 
  avatar_url = @avatarUrl, 
  updated_at = now()
WHERE id = @userId
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at, settings
''';

const _undoAccountDeletion = '''
UPDATE profiles
SET
  account_deletion_schedule = NULL,
  scheduled_for_deletion_at = NULL
WHERE id = @userId
RETURNING id, email, username, avatar_url, scheduled_for_deletion_at, settings
''';

const _deleteAccount = '''
DELETE FROM profiles
WHERE id = @userId
''';

const _listExercises = '''
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', e.id,
      -- the env-stable content slug (null for user-created rows); identity
      -- for content and fixtures, while the uuid is the wire identity
      'key', e.key,
      'name', COALESCE(t.name, tb.name, e.name),
      'category', e.category,
      'target', e.target,
      'instructions', COALESCE(t.instructions, tb.instructions, e.instructions),
      -- tracks whichever copy the locale joins serve, not COALESCE: a
      -- translation's NULL flag must not fall through to the fallback's
      'validated', CASE
        WHEN t.exercise_id IS NOT NULL THEN t.validated
        WHEN tb.exercise_id IS NOT NULL THEN tb.validated
        ELSE e.validated
      END,
      'asset', e.asset,
      'thumbnail', e.thumbnail,
      'muscles', e.muscles,
      'movement', e.movement,
      'health', e.health,
      'own', e.user_id IS NOT NULL,
      'archived', e.archived,
      'unit_system', ep.unit_system,
      'rest_timer', ep.rest_timer
    ) ORDER BY e.name
  ),
  '[]'::jsonb
) AS exercises
FROM exercises e
LEFT JOIN exercise_translations t ON t.exercise_id = e.id AND t.locale = @locale
-- the regional fallback chain (es_ES -> es -> en): a regional locale with no
-- row of its own must serve its base language, not jump straight to the
-- master columns. @baseLocale is the language part of @locale; the DISTINCT
-- guard keeps base-locale requests to a single join.
LEFT JOIN exercise_translations tb
  ON tb.exercise_id = e.id AND tb.locale = @baseLocale AND @baseLocale IS DISTINCT FROM @locale
LEFT JOIN exercise_preferences ep ON ep.exercise_id = e.id AND ep.user_id = @userId
WHERE
  CASE WHEN @owned::boolean
    THEN e.user_id = @userId
    ELSE e.user_id IS NULL OR e.user_id = @userId
  END
''';

/// Idempotent create for a custom exercise, the upsync replay's first resource
/// (heart-api#66): a client id already owned by the caller, or a name
/// (case-insensitively — matching the import path's own notion) the caller
/// already uses, resolves to that existing row with `created = false` rather
/// than erroring. Both pre-checks are scoped to `user_id = @userId`, so an id
/// that belongs to someone else (or a global exercise) matches neither CTE and
/// falls through to the plain INSERT, which then trips the real
/// `exercises_pkey` violation — caught and rethrown as `403 id_taken` by
/// `_rethrowForeignId`, never silently absorbed.
const _createExercise = '''
WITH
_by_id AS (
  SELECT id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived, user_id
  FROM exercises
  WHERE id = @id::uuid AND user_id = @userId
),
_by_name AS (
  -- the real unique index (exercises_user_name_idx) is case-sensitive; the
  -- match here is deliberately looser (case-insensitive, matching the CSV
  -- import's own notion of "the same exercise"), so pre-existing case-variant
  -- rows are a real if rare possibility — LIMIT 1 keeps this CTE single-row
  SELECT id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived, user_id
  FROM exercises
  WHERE user_id = @userId AND lower(name) = lower(@name)
  ORDER BY id
  LIMIT 1
),
_ins AS (
  INSERT INTO exercises (id, name, category, target, instructions, user_id)
  -- the app mints a v7 id at construction (offline-first needs identity
  -- before the server ack) and it round-trips here; absent, the column
  -- default mints one
  SELECT coalesce(@id::uuid, uuidv7()), @name, @category, @target, @instructions, @userId
  WHERE NOT EXISTS (SELECT 1 FROM _by_id) AND NOT EXISTS (SELECT 1 FROM _by_name)
  RETURNING id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived, user_id
)
SELECT id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived,
       user_id IS NOT NULL AS own, true AS created
FROM _ins
UNION ALL
SELECT id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived,
       user_id IS NOT NULL AS own, false AS created
FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
UNION ALL
SELECT id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived,
       user_id IS NOT NULL AS own, false AS created
FROM _by_name
WHERE NOT EXISTS (SELECT 1 FROM _ins) AND NOT EXISTS (SELECT 1 FROM _by_id)
''';

const _updateExercise = '''
UPDATE exercises
SET
  category = coalesce(@category, category),
  target = coalesce(@target, target),
  instructions = coalesce(@instructions, instructions),
  archived = coalesce(@archived, archived)
WHERE id = @exerciseId::uuid 
  AND user_id = @userId
RETURNING id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived,
          user_id IS NOT NULL AS own
''';

const _setExerciseMedia = '''
UPDATE exercises
SET
  asset = @asset::jsonb,
  thumbnail = @thumbnail::jsonb
WHERE key = @key 
  AND user_id IS NULL
RETURNING id
''';

const _createConnection = '''
WITH target_exists AS (
  SELECT 1 FROM profiles WHERE id = @targetId
),
inserted AS (
  INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status_by)
  SELECT @initiatorId, @targetId, @initiatorRole, @targetRole, @domain, @initiatorId
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

const _listConnections = '''
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

const _getConnection = '''
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

/// Severing is either party's call — except while a block stands, when only the
/// blocker may remove the row. Without that, blocking someone is undone by the
/// person you blocked, since a hard delete makes them re-requestable.
///
/// Returns one row either way: `existed` separates "already gone" (a no-op, as
/// it has always been) from `deleted` false, which is a refusal.
const _deleteConnection = '''
WITH
_pair AS (
  SELECT status, status_by FROM connections
  WHERE (initiator_id, target_id, domain) IN (
    (@actorId, @targetId, @domain),
    (@targetId, @actorId, @domain)
  )
),
_deleted AS (
  DELETE FROM connections
  WHERE (initiator_id, target_id, domain) IN (
    (@actorId, @targetId, @domain),
    (@targetId, @actorId, @domain)
  )
  AND EXISTS (SELECT 1 FROM _pair WHERE status <> 'blocked' OR status_by = @actorId)
  RETURNING 1
)
SELECT
  EXISTS (SELECT 1 FROM _deleted) AS deleted,
  EXISTS (SELECT 1 FROM _pair) AS existed
''';

/// The two rules that turn on *which* side is asking, enforced here rather than
/// in Dart so they cannot be raced past:
///
/// - accepting or declining a request belongs to the person who received it; the
///   author of a pending request must not be able to approve their own.
/// - only whoever set a block may lift it.
///
/// `@expectedStatus` makes the write optimistic-locked against the status the
/// caller read, so a concurrent change loses rather than silently overwriting.
const _updateConnectionStatus = '''
UPDATE connections SET status = @newStatus, status_by = @actorId
WHERE (initiator_id, target_id, domain) IN (
  (@actorId, @targetId, @domain),
  (@targetId, @actorId, @domain)
)
AND status = @expectedStatus
AND (@newStatus NOT IN ('active', 'declined') OR status <> 'pending' OR initiator_id <> @actorId)
AND (status <> 'blocked' OR status_by = @actorId)
RETURNING status
''';

const _listWorkouts = '''
WITH
_auth AS (
  SELECT (
    @requesterId::text = @targetUserId::text
    OR EXISTS (
      -- status matters: a pending request the other person has never seen, or a
      -- declined/severed/blocked one, is not permission to read their history.
      SELECT 1 FROM connections
      WHERE status = 'active'
        AND (
          (initiator_id = @requesterId AND target_id = @targetUserId AND initiator_role IN ('COACH', 'PEER'))
          OR
          (initiator_id = @targetUserId AND target_id = @requesterId AND target_role IN ('COACH', 'PEER'))
        )
    )
  ) AS allowed
),
_workouts AS (
  SELECT
    id, name, started_at, completed_at, calories, created_at,
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
SELECT id, name, started_at, completed_at, calories, created_at, exercises, images, false AS forbidden FROM _workouts
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _auth WHERE NOT allowed
''';

const _getWorkout = '''
SELECT
  w.id,
  w.name,
  w.started_at,
  w.completed_at,
  w.calories,
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

const _getTargetWorkout = '''
WITH
_auth AS (
  SELECT (
    @requesterId::text = @targetUserId::text
    OR EXISTS (
      -- status matters: a pending request the other person has never seen, or a
      -- declined/severed/blocked one, is not permission to read their history.
      SELECT 1 FROM connections
      WHERE status = 'active'
        AND (
          (initiator_id = @requesterId AND target_id = @targetUserId AND initiator_role IN ('COACH', 'PEER'))
          OR
          (initiator_id = @targetUserId AND target_id = @requesterId AND target_role IN ('COACH', 'PEER'))
        )
    )
  ) AS allowed
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.calories, w.created_at,
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
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _auth WHERE NOT allowed
''';

/// Idempotent create for a workout, the replay's fifth resource
/// (heart-api#66): a client id the caller already owns is never
/// re-inserted — its exercises and sets are skipped wholesale (the
/// `_inserted_exercises` CROSS JOIN against `_workout` naturally yields no rows
/// once `_workout`'s INSERT is guarded away), and the existing row is fetched
/// instead, `created = false`. A retried child id under the *same* workout id
/// therefore never touches `workout_exercises`/`exercise_sets` a second time; a
/// child id reused under a *different* workout id still hits the real pkey and
/// 400s, unchanged. An id owned by someone else matches neither branch, so the
/// INSERT is attempted and trips `workouts_pkey` — `403 id_taken` via
/// `_rethrowForeignId`.
const _saveWorkout = '''
WITH
_existing_workout AS (
  SELECT id FROM workouts WHERE id = @id::uuid AND user_id = @userId
),
_order_to_id AS (
  SELECT
    -- ids round-trip, same as _replaceWorkout: the exercise id the client
    -- minted mid-workout carries the instant the exercise was started, and
    -- that is what the act history reads back
    (ex->>'id')::uuid AS id,
    (ex->>'start')::timestamptz AS started_at,
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id,
    (ex->>'met')::real AS met,
    ex->>'note' AS note
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  -- ids are unique, so the old DISTINCT ON (name) user-over-global tie-break
  -- is gone; visibility still scopes to globals plus the caller's own rows,
  -- and a reference to anything else drops the row via the join below
  SELECT DISTINCT e.id AS exercise_id
  FROM exercises e
  JOIN _order_to_id otn ON otn.exercise_id = e.id
  WHERE e.user_id IS NULL OR e.user_id = @userId
),
_workout AS (
  INSERT INTO workouts (id, user_id, name, started_at, completed_at, calories)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @name, @startedAt, @completedAt, @calories
  WHERE NOT EXISTS (SELECT 1 FROM _existing_workout)
  RETURNING id, name, started_at, completed_at, calories, created_at
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order, met, note)
  SELECT
    coalesce(otn.id, uuidv7(coalesce(otn.started_at, clock_timestamp()))),
    w.id,
    el.exercise_id,
    otn.exercise_order,
    otn.met,
    otn.note
  FROM _workout w
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  RETURNING id, exercise_order, met, note
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
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order)
  SELECT
    coalesce((si.set_data->>'id')::uuid, uuidv7()),
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    coalesce((si.set_data->>'completed')::boolean, false),
    (si.set_data->>'started_at')::timestamptz,
    (si.set_data->>'completed_at')::timestamptz,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order
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
        'completed_at', completed_at,
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
        'name', e.name
      ),
      'exercise_order', ie.exercise_order,
      'met', ie.met,
      'note', ie.note,
      'sets', COALESCE(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _order_to_id otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT
  w.id,
  w.name,
  w.started_at,
  w.completed_at,
  w.calories,
  w.created_at,
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises,
  '[]'::jsonb AS images,
  true AS created
FROM _workout w
LEFT JOIN _exercises_json ej
  ON true
UNION ALL
SELECT
  w.id,
  w.name,
  w.started_at,
  w.completed_at,
  w.calories,
  w.created_at,
  _workout_exercises(w.id) AS exercises,
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) AS images,
  false AS created
FROM workouts w
WHERE w.id IN (SELECT id FROM _existing_workout)
''';

/// Whole CSV import in one atomic statement. Unlike [_saveWorkout]'s lookup —
/// which silently drops exercises it can't resolve — unknown names are created
/// as the user's custom exercises, gated by consent: a non-null @createCustom
/// is the allowlist of unmatched names the user approved (NULL = approve all,
/// the pre-consent behavior). Declined names fall out of _lookup, taking their
/// workout_exercises and sets with them — counted in the report, never silent.
/// Workouts left with no surviving exercise aren't created at all, so their
/// import identity stays unclaimed and a later consenting re-import recovers
/// them in full.
/// Workouts land with ON CONFLICT DO NOTHING on (user_id, import_id): re-running
/// the same export inserts nothing and the report shows it. Ids — the
/// workout's and its exercises'/sets' alike — are uuid-v7 minted at the
/// workout's *start* time, because history pages by id: an import of
/// years-old workouts must land deep in pagination, not on page one, and a
/// child id shouldn't contradict its own workout's timeline.
const _importWorkouts = '''
WITH
_incoming AS (
  SELECT w AS workout, w->>'importId' AS import_id
  FROM jsonb_array_elements(@workouts::jsonb) w
),
_names AS (
  SELECT ex->>'name' AS name, ex->>'category' AS category, ex->>'target' AS target
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
-- keyed by the *incoming* name so downstream joins on the CSV's spelling still
-- hit; matching is case-insensitive because that is the DB's own notion of
-- identity (unique on (user_id, lower(name)))
_resolved AS (
  SELECT DISTINCT ON (n.name) n.name, e.id
  FROM exercises e
  JOIN _names n ON lower(n.name) = lower(e.name)
  WHERE e.user_id IS NULL OR e.user_id = @userId
  ORDER BY n.name, e.user_id NULLS LAST
),
_already_imported AS (
  SELECT i.import_id
  FROM _incoming i
  WHERE exists (SELECT 1 FROM workouts w WHERE w.user_id = @userId AND w.import_id = i.import_id)
),
_created_exercises AS (
  INSERT INTO exercises (name, category, target, user_id)
  -- DISTINCT ON folds case-variant spellings of one exercise into a single
  -- custom; inserting both would trip unique (user_id, lower(name))
  SELECT DISTINCT ON (lower(n.name)) n.name, n.category, n.target, @userId
  FROM _names n
  WHERE NOT exists (SELECT 1 FROM _resolved r WHERE lower(r.name) = lower(n.name))
    AND (@createCustom::jsonb IS NULL OR n.name IN (SELECT jsonb_array_elements_text(@createCustom::jsonb)))
  ORDER BY lower(n.name), n.name
  RETURNING id, name
),
-- case-folded name -> exercise id; DISTINCT because two case-variant incoming
-- names resolve to the same id and must not fan out the joins below
_lookup AS (
  SELECT DISTINCT lower(name) AS name, id
  FROM (
    SELECT name, id FROM _resolved
    UNION ALL
    SELECT name, id FROM _created_exercises
  ) _all
),
_inserted_workouts AS (
  INSERT INTO workouts (id, user_id, name, started_at, completed_at, import_id)
  SELECT uuidv7((i.workout->>'start')::timestamptz), @userId, NULLIF(i.workout->>'name', ''), (i.workout->>'start')::timestamptz, (i.workout->>'end')::timestamptz, i.import_id
  FROM _incoming i
  WHERE exists (
    SELECT 1 FROM jsonb_array_elements(i.workout->'exercises') ex
    JOIN _lookup l ON l.name = lower(ex->>'name')
  )
  ON CONFLICT (user_id, import_id) WHERE import_id IS NOT NULL DO NOTHING
  RETURNING id, import_id
),
_exercises_in AS (
  SELECT iw.id AS workout_id, (i.workout->>'start')::timestamptz AS started_at,
         ex AS exercise, (ex->>'order')::int AS exercise_order
  FROM _inserted_workouts iw
  JOIN _incoming i ON i.import_id = iw.import_id
  CROSS JOIN LATERAL jsonb_array_elements(i.workout->'exercises') ex
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order)
  SELECT uuidv7(e.started_at), e.workout_id, l.id, e.exercise_order
  FROM _exercises_in e
  JOIN _lookup l ON l.name = lower(e.exercise->>'name')
  RETURNING id, workout_id, exercise_order
),
_sets_in AS (
  SELECT e.workout_id, e.started_at, e.exercise_order, t.s AS set_data, (t.ordinality - 1)::int AS set_order
  FROM _exercises_in e
  CROSS JOIN LATERAL jsonb_array_elements(e.exercise->'sets') WITH ORDINALITY t(s, ordinality)
),
_inserted_sets AS (
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, set_order)
  SELECT
    uuidv7(si.started_at),
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    true,
    si.set_order
  FROM _sets_in si
  JOIN _inserted_exercises ie ON ie.workout_id = si.workout_id AND ie.exercise_order = si.exercise_order
  RETURNING id
)
SELECT
  (SELECT count(*) FROM _incoming)::int AS workouts_found,
  (SELECT count(*) FROM _inserted_workouts)::int AS workouts_created,
  (SELECT count(*) FROM _inserted_sets)::int AS sets_created,
  -- sets lost to declined names, over workouts this run actually considered
  -- (already-imported ones were never going to contribute sets)
  (SELECT count(*)
   FROM _incoming i
   CROSS JOIN LATERAL jsonb_array_elements(i.workout->'exercises') ex
   CROSS JOIN LATERAL jsonb_array_elements(ex->'sets') s
   WHERE NOT EXISTS (SELECT 1 FROM _already_imported a WHERE a.import_id = i.import_id)
     AND NOT EXISTS (SELECT 1 FROM _lookup l WHERE l.name = lower(ex->>'name')))::int AS sets_skipped,
  (SELECT count(*) FROM _resolved)::int AS exercises_matched,
  COALESCE((SELECT jsonb_agg(name ORDER BY name) FROM _created_exercises), '[]'::jsonb) AS exercises_created,
  COALESCE(
    (SELECT jsonb_agg(n.name ORDER BY n.name)
     FROM _names n
     WHERE NOT EXISTS (SELECT 1 FROM _lookup l WHERE l.name = lower(n.name))),
    '[]'::jsonb
  ) AS exercises_skipped
''';

/// The `dryRun=true` half of the import: resolves the batch's exercise names
/// and import identities against what the user already has, writing nothing.
/// Everything else the preview reports comes from the parsed batch in Dart.
const _previewImport = '''
WITH
_incoming AS (
  SELECT w->>'importId' AS import_id
  FROM jsonb_array_elements(@workouts::jsonb) w
),
_names AS (
  SELECT ex->>'name' AS name
  FROM jsonb_array_elements(@exercises::jsonb) ex
)
SELECT
  (SELECT count(*)
   FROM _incoming i
   WHERE EXISTS (SELECT 1 FROM workouts w WHERE w.user_id = @userId AND w.import_id = i.import_id))::int
    AS workouts_already_imported,
  -- the *incoming* spellings that matched: the caller set-subtracts these from
  -- the batch's names, so DB-cased names would misreport case-variant matches
  COALESCE(
    (SELECT jsonb_agg(DISTINCT n.name)
     FROM _names n
     WHERE EXISTS (
       SELECT 1 FROM exercises e
       WHERE lower(e.name) = lower(n.name) AND (e.user_id IS NULL OR e.user_id = @userId)
     )),
    '[]'::jsonb
  ) AS exercises_matched
''';

const _replaceWorkout = '''
WITH
_order_to_id AS (
  SELECT
    -- ids round-trip: the clients read an act's start off the exercise id's
    -- v7 mint instant, so a replace that re-minted moved every act to "now".
    -- WorkoutRequest only lets a valid v7 through, so the cast is safe; a row
    -- arriving without one is minted at the exercise's own start.
    (ex->>'id')::uuid AS id,
    (ex->>'start')::timestamptz AS started_at,
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id,
    (ex->>'met')::real AS met,
    ex->>'note' AS note
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  -- ids are unique, so the old DISTINCT ON (name) user-over-global tie-break
  -- is gone; visibility still scopes to globals plus the caller's own rows,
  -- and a reference to anything else drops the row via the join below
  SELECT DISTINCT e.id AS exercise_id
  FROM exercises e
  JOIN _order_to_id otn ON otn.exercise_id = e.id
  WHERE e.user_id IS NULL OR e.user_id = @userId
),
_workout AS (
  UPDATE workouts
  SET name = @name, started_at = @startedAt, completed_at = @completedAt, calories = @calories
  WHERE id = @workoutId::uuid AND user_id = @userId
  RETURNING id, name, started_at, completed_at, calories, created_at
),
_deleted_sets AS (
  -- explicit, not left to the ON DELETE CASCADE: a cascade is an AFTER
  -- trigger whose timing against the re-insert below is unspecified, and a
  -- round-tripped set id must land after its old row is already dead
  DELETE FROM exercise_sets
  WHERE workout_exercise_id IN (
    SELECT id FROM workout_exercises WHERE workout_id = (SELECT id FROM _workout)
  )
  RETURNING id
),
_deleted AS (
  DELETE FROM workout_exercises
  WHERE workout_id = (SELECT id FROM _workout)
  RETURNING id
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order, met, note)
  SELECT
    coalesce(otn.id, uuidv7(coalesce(otn.started_at, clock_timestamp()))),
    w.id,
    el.exercise_id,
    otn.exercise_order,
    otn.met,
    otn.note
  FROM _workout w
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  -- forces _deleted to run to completion first. The old form
  -- (NOT exists(... WHERE false)) constant-folded away, which left the
  -- delete/insert order unspecified — harmless while every insert minted a
  -- fresh id, a duplicate-key violation now that ids round-trip.
  WHERE (SELECT count(*) FROM _deleted) IS NOT NULL
  RETURNING id, exercise_order, met, note
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
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order)
  SELECT
    coalesce((si.set_data->>'id')::uuid, uuidv7()),
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    COALESCE((si.set_data->>'completed')::boolean, false),
    (si.set_data->>'started_at')::timestamptz,
    (si.set_data->>'completed_at')::timestamptz,
    si.set_order
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  -- sequenced after the explicit sets delete, same reason as _inserted_exercises
  WHERE (SELECT count(*) FROM _deleted_sets) IS NOT NULL
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order
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
        'completed_at', completed_at,
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
        'name', e.name
      ),
      'exercise_order', ie.exercise_order,
      'met', ie.met,
      'note', ie.note,
      'sets', coalesce(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _inserted_exercises ie
  JOIN _order_to_id otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.calories, w.created_at,
  coalesce(ej.exercises_json, '[]'::jsonb) AS exercises,
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) AS images
FROM _workout w
LEFT JOIN _exercises_json ej ON true
''';

const _patchWorkout = '''
WITH _updated AS (
  UPDATE workouts
  SET
    name = coalesce(@name::TEXT, name),
    started_at = coalesce(@startedAt::TIMESTAMPTZ, started_at),
    completed_at = coalesce(@completedAt::TIMESTAMPTZ, completed_at),
    calories = coalesce(@calories::REAL, calories)
  WHERE id = @workoutId::uuid AND user_id = @userId
  RETURNING id, name, started_at, completed_at, calories, created_at
)
SELECT
  u.id,
  u.name,
  u.started_at,
  u.completed_at,
  u.calories,
  u.created_at,
  _workout_exercises(u.id) AS exercises,
  coalesce(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', wi.id,
          'key', wi.key, 
          'workout_id', wi.workout_id
        ) 
        ORDER BY wi.id DESC
      )
     FROM workout_images wi WHERE wi.workout_id = u.id
    ),
    '[]'::jsonb
  ) AS images
FROM _updated u
''';

const _deleteWorkout = '''
DELETE FROM workouts 
WHERE id = @workoutId::uuid 
  AND user_id = @userId
''';

/// Idempotent create for a template, the replay's third resource
/// (heart-api#66): templates carry no natural key (decision 2 in
/// heart-api#66 — two templates may share a name), so only a client id
/// the caller already owns short-circuits the insert; the existing row is
/// fetched via `_template_exercises`, same shape as `_getTemplate`. An id owned
/// by someone else reaches the INSERT regardless of `@folderId` (see
/// `_foreign_template`, which keeps a bad folder from masking the id
/// conflict) and trips `templates_pkey` — `403 id_taken` via
/// `_rethrowForeignId`.
const _saveTemplate = '''
WITH
_existing_template AS (
  SELECT id FROM templates WHERE id = @id::uuid AND user_id = @userId
),
-- an id belonging to someone else must still reach the INSERT and trip
-- templates_pkey (-> 403 id_taken) even when @folderId is also invalid — the
-- folder guard below must not mask a foreign-id conflict behind a 404
_foreign_template AS (
  SELECT 1 FROM templates WHERE id = @id::uuid AND user_id <> @userId
),
_folder AS (
  SELECT id FROM template_folders
  WHERE id = @folderId::uuid AND user_id = @userId
),
_order_to_id AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  -- ids are unique, so the old DISTINCT ON (name) user-over-global tie-break
  -- is gone; visibility still scopes to globals plus the caller's own rows
  SELECT DISTINCT e.id, e.name, e.category, e.target
  FROM exercises e
  JOIN _order_to_id otn ON otn.exercise_id = e.id
  WHERE e.user_id IS NULL OR e.user_id = @userId
),
-- A folder the user does not own resolves to no row, so the INSERT selects
-- nothing and the mixin reports NotFound rather than silently unfiling.
_template AS (
  INSERT INTO templates (id, user_id, name, order_index, folder_id)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @name, @orderIndex, (SELECT id FROM _folder)
  WHERE NOT EXISTS (SELECT 1 FROM _existing_template)
    AND (
      EXISTS (SELECT 1 FROM _foreign_template)
      OR (@folderId::uuid IS NULL OR EXISTS (SELECT 1 FROM _folder))
    )
  RETURNING id, name, order_index, folder_id, source_template_id, assigned_by, sync_enabled, created_at
),
_inserted_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order)
  SELECT t.id, el.id, otn.exercise_order
  FROM _template t
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.id = otn.exercise_id
  RETURNING id, exercise_id, exercise_order
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
  t.folder_id,
  f.name AS folder_name,
  f.order_index AS folder_order,
  f.created_at AS folder_created_at,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  COALESCE(ej.exercises_json, '[]'::jsonb) AS exercises,
  true AS created
FROM _template t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
LEFT JOIN _exercises_json ej ON true
UNION ALL
SELECT
  t.id,
  t.name,
  t.order_index,
  t.folder_id,
  f.name AS folder_name,
  f.order_index AS folder_order,
  f.created_at AS folder_created_at,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  _template_exercises(t.id) AS exercises,
  false AS created
FROM templates t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.id IN (SELECT id FROM _existing_template)
''';

const _replaceTemplate = '''
WITH
_folder AS (
  SELECT id FROM template_folders
  WHERE id = @folderId::uuid AND user_id = @userId
),
_order_to_id AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id
  FROM jsonb_array_elements(@exercises::jsonb) ex
),
_exercise_lookup AS (
  -- ids are unique, so the old DISTINCT ON (name) user-over-global tie-break
  -- is gone; visibility still scopes to globals plus the caller's own rows
  SELECT DISTINCT e.id, e.name, e.category, e.target
  FROM exercises e
  JOIN _order_to_id otn ON otn.exercise_id = e.id
  WHERE e.user_id IS NULL OR e.user_id = @userId
),
-- @movesFolder distinguishes "the body said nothing about folderId" (leave it
-- where it is) from "the body said folderId: null" (unfile it). A folderId the
-- user does not own matches no row, so the update reports NotFound.
_template AS (
  UPDATE templates
  SET name = @name,
      order_index = @orderIndex,
      folder_id = CASE WHEN @movesFolder::boolean THEN (SELECT id FROM _folder) ELSE folder_id END
  WHERE id = @templateId::uuid AND user_id = @userId
    AND (NOT @movesFolder::boolean OR @folderId::uuid IS NULL OR EXISTS (SELECT 1 FROM _folder))
  RETURNING id, name, order_index, folder_id, source_template_id, assigned_by, sync_enabled, created_at
),
_deleted AS (
  DELETE FROM template_exercises WHERE template_id = (SELECT id FROM _template)
  RETURNING id
),
_inserted_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order)
  SELECT t.id, el.id, otn.exercise_order
  FROM _template t
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.id = otn.exercise_id
  WHERE NOT EXISTS (SELECT 1 FROM _deleted WHERE false)
  RETURNING id, exercise_id, exercise_order
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
  t.folder_id,
  f.name AS folder_name,
  f.order_index AS folder_order,
  f.created_at AS folder_created_at,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  COALESCE(ej.exercises_json, '[]'::jsonb) AS exercises
FROM _template t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
LEFT JOIN _exercises_json ej ON true
''';

const _getTemplate = '''
SELECT
  t.id,
  t.name,
  t.order_index,
  t.folder_id,
  f.name AS folder_name,
  f.order_index AS folder_order,
  f.created_at AS folder_created_at,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  _template_exercises(t.id) AS exercises
FROM templates t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.id = @templateId::uuid AND t.user_id = @userId
''';

/// Keyset-paginated on `(order_index, id)` ascending — the owner's arrangement,
/// with the id as tie-break because `order_index` is not unique. That pair is
/// also `Template.compareTo`'s ordering, so the app receives the list already in
/// the order its own model would sort it into. Backed by `templates_user_order_idx`.
///
/// The two folder predicates are mutually exclusive in practice: @folderId
/// narrows to one folder, @unfiledOnly to the templates in none; neither set
/// means everything.
const _listTemplates = '''
SELECT
  t.id,
  t.name,
  t.order_index,
  t.folder_id,
  f.name AS folder_name,
  f.order_index AS folder_order,
  f.created_at AS folder_created_at,
  t.source_template_id,
  t.assigned_by AS assigned_by_id,
  p.username AS assigned_by_username,
  p.avatar_url AS assigned_by_avatar,
  t.sync_enabled,
  t.created_at,
  _template_exercises(t.id) AS exercises
FROM templates t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.user_id = @userId
  AND (@cursorId::uuid IS NULL OR (t.order_index, t.id) > (@cursorOrder::int, @cursorId::uuid))
  AND (@folderId::uuid IS NULL OR t.folder_id = @folderId::uuid)
  AND (NOT @unfiledOnly::boolean OR t.folder_id IS NULL)
ORDER BY t.order_index, t.id
LIMIT @limit
''';

const _listTemplateShares = '''
SELECT
  ts.id AS id,
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

/// Assigns one or more of a coach's master templates to a student.
///
/// Two endpoints share this statement: assigning a single template (its id goes
/// in `@masterTemplateIds`) and assigning a whole folder (`@folderId`, and every
/// template filed there goes). `@folderId` wins when both are supplied.
///
/// Assignment **copies** rather than references — the student gets their own
/// templates, their own exercises and sets, and copies of any exercise their
/// library was missing — so nothing the coach edits later mutates a plan the
/// student is mid-way through. Idempotent per master: one already shared with
/// this student returns its existing share untouched, which is what makes
/// re-assigning a folder after adding one template to it safe.
///
/// Returns one row per master, plus a `forbidden` flag — the permission check is
/// per (coach, student), so it is the same on every row.
const _shareTemplates = '''
WITH
_student AS (
  SELECT id, username, avatar_url
  FROM profiles
  WHERE id = @studentId
),
_master AS (
  SELECT id, name
  FROM templates
  WHERE user_id = @coachId
    AND CASE
          WHEN @folderId::uuid IS NOT NULL THEN folder_id = @folderId::uuid
          ELSE id = ANY (@masterTemplateIds::uuid[])
        END
),
_existing AS (
  SELECT id, master_template_id, student_template_id, created_at
  FROM template_shares
  WHERE coach_id = @coachId
    AND student_id = @studentId
    AND master_template_id IN (SELECT id FROM _master)
),
-- The connection has to be live. A pending request, a declined one, or a
-- severed or blocked relationship is not a licence to push templates into
-- someone's library — matching `_areConnected`, which has always required this.
_allowed AS (
  SELECT 1 FROM connections
  WHERE status = 'active'
    AND (
      (initiator_id = @coachId AND target_id = @studentId AND initiator_role IN ('COACH', 'PEER'))
      OR
      (initiator_id = @studentId AND target_id = @coachId AND target_role IN ('COACH', 'PEER'))
    )
  LIMIT 1
),
-- Decided per master rather than per call: assigning a folder where three of
-- five templates already went must still send the other two.
_to_share AS (
  SELECT m.id, m.name
  FROM _master m
  WHERE EXISTS (SELECT 1 FROM _allowed)
    AND NOT EXISTS (SELECT 1 FROM _existing e WHERE e.master_template_id = m.id)
),
-- For each exercise the masters reference, capture its full data and look up
-- whichever exercise the student already has access to under the same name
-- (their own custom first, otherwise the global).
_master_exercises AS (
  SELECT
    te.template_id AS master_id,
    te.id AS source_te_id,
    te.exercise_order,
    e.name, e.category, e.target, e.instructions, e.asset, e.thumbnail, e.muscles, e.movement, e.health,
    (
      SELECT e2.id FROM exercises e2
      WHERE e2.name = e.name
        AND (e2.user_id IS NULL OR e2.user_id = @studentId)
      ORDER BY e2.user_id NULLS LAST
      LIMIT 1
    ) AS resolved_id
  FROM template_exercises te
  JOIN exercises e ON e.id = te.exercise_id
  WHERE te.template_id IN (SELECT id FROM _to_share)
),
-- Copy any unresolved exercises into the student's library so the FK holds.
-- DISTINCT ON dedupes across masters that name the same missing exercise.
_copied_exercises AS (
  INSERT INTO exercises (name, category, target, instructions, asset, thumbnail, muscles, movement, health, user_id)
  SELECT DISTINCT ON (name)
    name, category, target, instructions, asset, thumbnail, muscles, movement, health, @studentId
  FROM _master_exercises
  WHERE resolved_id IS NULL
  RETURNING id, name
),
-- The mapping of (master, exercise_order) → the exercise_id the student's copy
-- should reference.
_resolved_exercises AS (
  SELECT
    me.master_id,
    me.exercise_order,
    me.source_te_id,
    coalesce(me.resolved_id, c.id) AS exercise_id
  FROM _master_exercises me
  LEFT JOIN _copied_exercises c ON c.name = me.name AND me.resolved_id IS NULL
),
-- The student's copies land unfiled — folder_id defaults to NULL. The coach's
-- filing is the coach's business; the student organises their own library.
_new_template AS (
  INSERT INTO templates (user_id, name, order_index, source_template_id, assigned_by, sync_enabled)
  SELECT @studentId, s.name, 0, s.id, @coachId, true
  FROM _to_share s
  RETURNING id, source_template_id
),
_new_exercises AS (
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order)
  SELECT nt.id, re.exercise_id, re.exercise_order
  FROM _new_template nt
  JOIN _resolved_exercises re ON re.master_id = nt.source_template_id
  RETURNING id, template_id, exercise_order
),
_new_sets AS (
  INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, duration, distance, set_order)
  SELECT ne.id, tes.weight, tes.reps, tes.duration, tes.distance, tes.set_order
  FROM _new_exercises ne
  JOIN _new_template nt ON nt.id = ne.template_id
  JOIN _resolved_exercises re
    ON re.master_id = nt.source_template_id AND re.exercise_order = ne.exercise_order
  JOIN template_exercise_sets tes ON tes.template_exercise_id = re.source_te_id
  RETURNING id
),
_new_share AS (
  INSERT INTO template_shares (coach_id, student_id, master_template_id, student_template_id)
  SELECT @coachId, @studentId, nt.source_template_id, nt.id
  FROM _new_template nt
  RETURNING id, master_template_id, student_template_id, created_at
)
SELECT
  COALESCE(ns.id, ex.id) AS id,
  s.id AS student_id,
  m.id AS master_template_id,
  COALESCE(ns.student_template_id, ex.student_template_id) AS student_template_id,
  m.name AS template_name,
  s.username AS student_username,
  s.avatar_url AS student_avatar,
  COALESCE(ns.created_at, ex.created_at) AS created_at,
  NOT EXISTS (SELECT 1 FROM _allowed) AS forbidden
FROM _student s
CROSS JOIN _master m
LEFT JOIN _new_share ns ON ns.master_template_id = m.id
LEFT JOIN _existing ex ON ex.master_template_id = m.id
ORDER BY m.id
''';

const _deleteTemplate = '''
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

const _deleteShare = '''
WITH
_deleted AS (
  DELETE FROM templates
  WHERE id = (
    SELECT student_template_id FROM template_shares
    WHERE id = @shareId::uuid AND coach_id = @coachId
  )
  RETURNING id
)
SELECT id FROM _deleted
''';

const _listTemplateFolders = '''
SELECT
  f.id,
  f.name,
  f.order_index,
  f.created_at,
  count(t.id) AS template_count
FROM template_folders f
LEFT JOIN templates t ON t.folder_id = f.id
WHERE f.user_id = @userId
GROUP BY f.id
ORDER BY f.order_index, lower(f.name)
''';

/// Idempotent create for a folder, the replay's second resource
/// (heart-api#66): a client id the caller already owns, or a name (on
/// the case-insensitive index) the caller already has, resolves to that
/// existing folder with `created = false` — replacing the old `400 "you
/// already have a folder called..."`. An id owned by someone else matches
/// neither pre-check and falls through to the plain INSERT, tripping
/// `template_folders_pkey` — `403 id_taken` via `_rethrowForeignId`.
const _createTemplateFolder = '''
WITH
_by_id AS (
  SELECT id, name, order_index, created_at FROM template_folders
  WHERE id = @id::uuid AND user_id = @userId
),
_by_name AS (
  -- the real unique index (template_folders_user_name_idx) already keys on
  -- lower(name), so this can only ever match one row; LIMIT 1 documents that
  -- rather than relying on it silently
  SELECT id, name, order_index, created_at FROM template_folders
  WHERE user_id = @userId AND lower(name) = lower(@name)
  ORDER BY id
  LIMIT 1
),
_ins AS (
  INSERT INTO template_folders (id, user_id, name, order_index)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @name, @orderIndex
  WHERE NOT EXISTS (SELECT 1 FROM _by_id) AND NOT EXISTS (SELECT 1 FROM _by_name)
  RETURNING id, name, order_index, created_at
)
SELECT id, name, order_index, created_at, 0 AS template_count, true AS created FROM _ins
UNION ALL
SELECT id, name, order_index, created_at, 0 AS template_count, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
UNION ALL
SELECT id, name, order_index, created_at, 0 AS template_count, false AS created FROM _by_name
WHERE NOT EXISTS (SELECT 1 FROM _ins) AND NOT EXISTS (SELECT 1 FROM _by_id)
''';

/// Three outcomes, told apart without a second round trip: no rows (the folder
/// is not the caller's), one row with `name_taken` (the rename would collide),
/// one row with the folder (renamed).
const _updateTemplateFolder = '''
WITH
_target AS (
  SELECT id FROM template_folders
  WHERE id = @folderId::uuid AND user_id = @userId
),
_conflict AS (
  SELECT 1 FROM template_folders
  WHERE user_id = @userId
    AND lower(name) = lower(@name)
    AND id <> @folderId::uuid
),
_updated AS (
  UPDATE template_folders
  SET name = @name, order_index = @orderIndex
  WHERE id = (SELECT id FROM _target)
    AND NOT EXISTS (SELECT 1 FROM _conflict)
  RETURNING id, name, order_index, created_at
)
SELECT
  t.id,
  u.name,
  u.order_index,
  u.created_at,
  (SELECT count(*) FROM templates WHERE folder_id = t.id) AS template_count,
  EXISTS (SELECT 1 FROM _conflict) AS name_taken
FROM _target t
LEFT JOIN _updated u ON u.id = t.id
''';

/// The templates inside survive — `templates_folder_fk` is `ON DELETE SET NULL
/// (folder_id)`, so they come back unfiled rather than being destroyed.
const _deleteTemplateFolder = '''
DELETE FROM template_folders
WHERE id = @folderId::uuid AND user_id = @userId
RETURNING id
''';

/// Runs only when a folder assignment shared nothing, to tell the three causes
/// apart: an unknown folder, an unknown student, or a folder that is simply
/// empty. One row, always.
const _diagnoseEmptyFolderShare = '''
SELECT
  EXISTS (SELECT 1 FROM template_folders WHERE id = @folderId::uuid AND user_id = @coachId) AS folder_exists,
  EXISTS (SELECT 1 FROM profiles WHERE id = @studentId) AS student_exists
''';

const _areConnected = '''
SELECT 1 FROM connections
WHERE status = 'active'
  AND (
    (initiator_id = @userA AND target_id = @userB)
    OR
    (initiator_id = @userB AND target_id = @userA)
  )
LIMIT 1
''';

const _resolveCommentTargetOwner = '''
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

const _insertComment = '''
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

const _listComments = '''
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

const _updateComment = '''
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

const _deleteComment = '''
DELETE FROM comments
WHERE id = @commentId::uuid AND author_id = @authorId
RETURNING id
''';

const _upsertDevice = '''
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

const _listDeviceTokensWithLocale = '''
SELECT token, locale FROM device_tokens WHERE profile_id = @profileId
''';

const _deleteDeviceToken = '''
DELETE FROM device_tokens WHERE token = @token
''';

const _saveExercisePreference = '''
INSERT INTO exercise_preferences (user_id, exercise_id, unit_system, rest_timer)
VALUES (@userId, @exerciseId::uuid, @unitSystem::text, @restTimer::integer)
ON CONFLICT (user_id, exercise_id)
DO UPDATE SET
  unit_system = COALESCE(EXCLUDED.unit_system, exercise_preferences.unit_system),
  rest_timer  = COALESCE(EXCLUDED.rest_timer, exercise_preferences.rest_timer)
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

const _getChartPreferences = '''
SELECT 
  exercise_id AS id, 
  chart_type AS type
FROM exercise_preferences 
WHERE user_id = @userId 
  AND chart_type IS NOT NULL 
ORDER BY created_at DESC
;
''';

const _saveChartPreference = '''
INSERT INTO exercise_preferences (user_id, exercise_id, chart_type)
VALUES (@userId, @exerciseId::uuid, @chartType)
ON CONFLICT (user_id, exercise_id)
DO 
  UPDATE SET chart_type = @chartType
''';

const _deleteChartPreference = '''
UPDATE exercise_preferences 
SET chart_type = NULL
WHERE exercise_id = @id::uuid
  AND user_id = @userId
  ;
''';

// Goals are visible to their owner and to active connections, exactly like
// workouts (see _listWorkouts) — the auth CTE is identical. Writing stays
// owner-only; this is the only cross-user read. A forbidden requester gets a
// single sentinel row, which the db layer turns into a 403.
const _listTargetGoals = '''
WITH
_auth AS (
  SELECT (
    @requesterId::text = @targetUserId::text
    OR EXISTS (
      SELECT 1 FROM connections
      WHERE status = 'active'
        AND (
          (initiator_id = @requesterId AND target_id = @targetUserId AND initiator_role IN ('COACH', 'PEER'))
          OR
          (initiator_id = @targetUserId AND target_id = @requesterId AND target_role IN ('COACH', 'PEER'))
        )
    )
  ) AS allowed
),
_goals AS (
  SELECT id, metric, exercise_id, cadence, stages, archived, created_at
  FROM goals
  WHERE (SELECT allowed FROM _auth)
    AND user_id = @targetUserId::text
    AND archived = @archived::boolean
  ORDER BY created_at
)
SELECT id, metric, exercise_id, cadence, stages, archived, created_at, false AS forbidden FROM _goals
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _auth WHERE NOT allowed
''';

/// A user keeps a bounded number of live goals — enough for every sensible plan,
/// low enough that the unpaginated list stays cheap and no one can flood the table.
const _maxActiveGoals = 50;

// The cap is enforced in the INSERT, not read-then-write in Dart, so two concurrent
// creates can't both pass a stale count and land a 51st. A full table returns no row,
// which the db layer turns into a 400.
//
// Idempotent create, the replay's last resource (heart-api#66): a client
// id the caller already owns short-circuits the insert (and the cap check —
// a retry must never count against the ceiling it already cleared), returning
// the existing goal with `created = false`. Goals have no natural key, so this
// is the only pre-check.
//
// The cap must not be allowed to mask a foreign-id conflict: an id belonging
// to someone else has to reach the INSERT and trip `goals_pkey` — `403
// id_taken` via `_rethrowForeignId` — even when the caller is at their own
// cap, so `_foreign` short-circuits the cap check in that case (`OR`, not
// `AND`). Only when the id is genuinely free does the cap gate the insert; a
// genuinely empty result (no `_by_id`, no `_foreign`, no `_ins`, no
// exception) is then unambiguously the cap.
const _createGoal =
    '''
WITH
_by_id AS (
  SELECT id, metric, exercise_id, cadence, stages, archived, created_at
  FROM goals WHERE id = @id::uuid AND user_id = @userId
),
_foreign AS (
  SELECT 1 FROM goals WHERE id = @id::uuid AND user_id <> @userId
),
_ins AS (
  INSERT INTO goals (id, user_id, metric, exercise_id, cadence, stages)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @metric::text, @exerciseId::uuid, @cadence::text, @stages::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM _by_id)
    AND (
      EXISTS (SELECT 1 FROM _foreign)
      OR (SELECT count(*) FROM goals WHERE user_id = @userId AND NOT archived) < $_maxActiveGoals
    )
  RETURNING id, metric, exercise_id, cadence, stages, archived, created_at
)
SELECT id, metric, exercise_id, cadence, stages, archived, created_at, true AS created FROM _ins
UNION ALL
SELECT id, metric, exercise_id, cadence, stages, archived, created_at, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

const _updateGoal = '''
UPDATE goals
SET metric      = @metric::text,
    exercise_id = @exerciseId::uuid,
    cadence     = @cadence::text,
    stages      = @stages::jsonb,
    archived    = @archived::boolean
WHERE id = @id::uuid
  AND user_id = @userId
RETURNING id, metric, exercise_id, cadence, stages, archived, created_at
''';

const _deleteGoal = '''
DELETE FROM goals
WHERE id = @id::uuid
  AND user_id = @userId
''';

// Addresses the stage by its id, never by array position, so a reordered ladder
// still resolves. The EXISTS guard is load-bearing: without it an unknown stage id
// makes the path subquery NULL and jsonb_set raises "path element at position 1 is
// null" — a 500. With it, no match means no rows, and the route turns that into 404.
const _markStageAchieved = '''
UPDATE goals
SET stages = jsonb_set(
        stages,
        ARRAY[(
            SELECT (ordinality - 1)::text
            FROM jsonb_array_elements(stages) WITH ORDINALITY AS s(stage, ordinality)
            WHERE stage ->> 'id' = @stageId
        )],
        (
            -- strip_nulls keeps achievedBy out of the blob when it is absent; a
            -- present value merges (and overwrites) alongside achievedAt.
            SELECT stage || jsonb_strip_nulls(
                jsonb_build_object('achievedAt', @achievedAt::text, 'achievedBy', @achievedBy::text)
            )
            FROM jsonb_array_elements(stages) AS stage
            WHERE stage ->> 'id' = @stageId
        )
    )
WHERE id = @goalId::uuid
  AND user_id = @userId
  AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(stages) AS stage
      WHERE stage ->> 'id' = @stageId
  )
RETURNING id, metric, exercise_id, cadence, stages, archived, created_at
''';
