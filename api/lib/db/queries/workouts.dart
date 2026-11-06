part of '../db.dart';

const _listWorkouts = '''
WITH
_rel AS (
  SELECT _relation(@requesterId, @targetUserId) AS r
),
_workouts AS (
  SELECT
    id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, created_at,
    logged_by,
    (SELECT username FROM profiles coach WHERE coach.id = workouts.logged_by) AS logged_by_name,
    _workout_exercises(id) AS exercises,
    CASE
      WHEN (SELECT (r).scope FROM _rel) = 'coach' THEN '[]'::jsonb
      ELSE COALESCE(
        (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
         FROM workout_images wi WHERE wi.workout_id = workouts.id),
        '[]'::jsonb
      )
    END AS images
  FROM workouts
  WHERE user_id = @targetUserId::text
    AND _readable_at((SELECT r FROM _rel), started_at, hidden_at)
    AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
  ORDER BY id DESC
  LIMIT @limit
)
SELECT id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, created_at, logged_by, logged_by_name, exercises, images, false AS forbidden FROM _workouts
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _rel WHERE (r).scope IS NULL
''';

/// Hiding what is already hidden keeps the first time. Either way the answer is
/// the workout, so one that isn't the caller's, or isn't here yet, reads as missing.
const _hideWorkout = '''
WITH
_hidden AS (
  UPDATE workouts
  SET hidden_at = least(coalesce(@at::timestamptz, now()), now())
  WHERE id = @workoutId::uuid
    AND user_id = @userId
    AND hidden_at IS NULL
  RETURNING id
)
SELECT id FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId
''';

const _unhideWorkout = '''
WITH
_shown AS (
  UPDATE workouts
  SET hidden_at = NULL
  WHERE id = @workoutId::uuid
    AND user_id = @userId
    AND hidden_at IS NOT NULL
  RETURNING id
)
SELECT id FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId
''';

const _listHiddenWorkouts = '''
SELECT id, hidden_at
FROM workouts
WHERE user_id = @userId
  AND hidden_at IS NOT NULL
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _getWorkout = '''
SELECT
  w.id,
  w.name,
  w.started_at,
  w.completed_at,
  w.calories,
  w.note,
  w.pauses,
  w.template_id,
  w.program_id,
  w.created_at,
  w.logged_by,
  (SELECT username FROM profiles coach WHERE coach.id = w.logged_by) AS logged_by_name,
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
_rel AS (
  SELECT _relation(@requesterId, @targetUserId) AS r
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.calories, w.note, w.pauses, w.template_id, w.program_id, w.created_at,
  w.logged_by,
  (SELECT username FROM profiles coach WHERE coach.id = w.logged_by) AS logged_by_name,
  _workout_exercises(w.id) AS exercises,
  CASE
    WHEN (SELECT (r).scope FROM _rel) = 'coach' THEN '[]'::jsonb
    ELSE COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
       FROM workout_images wi WHERE wi.workout_id = w.id),
      '[]'::jsonb
    )
  END AS images,
  false AS forbidden
FROM workouts w
WHERE w.id = @workoutId::uuid
  AND w.user_id = @targetUserId::text
  AND _readable_at((SELECT r FROM _rel), w.started_at, w.hidden_at)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _rel WHERE (r).scope IS NULL
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
-- the template and program are the caller's own or nothing: a session saved
-- before its template synced, or after it was deleted, still saves, unlinked
_template AS (
  SELECT id FROM templates WHERE id = @templateId::uuid AND user_id = @userId
),
_program AS (
  SELECT id FROM programs WHERE id = @programId::uuid AND user_id = @userId
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
    ex->>'note' AS note,
    (ex->>'superset')::smallint AS superset,
    -- a body that leaves the superset out (a build that predates it) keeps it
    ex ? 'superset' AS sets_superset
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
  INSERT INTO workouts (id, user_id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, logged_by)
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @name,
    @startedAt,
    @completedAt,
    @calories,
    @note,
    @pauses::jsonb,
    (SELECT id FROM _template),
    (SELECT id FROM _program),
    @loggedBy::text
  WHERE NOT EXISTS (SELECT 1 FROM _existing_workout)
  RETURNING id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, created_at, logged_by
),
_inserted_exercises AS (
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order, met, note, superset)
  SELECT
    coalesce(otn.id, uuidv7(coalesce(otn.started_at, clock_timestamp()))),
    w.id,
    el.exercise_id,
    otn.exercise_order,
    otn.met,
    otn.note,
    otn.superset
  FROM _workout w
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  RETURNING id, exercise_order, met, note, superset
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
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order, set_type, rpe, target)
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
    si.set_order,
    _set_type_code(si.set_data->>'set_type'),
    (si.set_data->>'rpe')::real,
    nullif(si.set_data->'target', 'null'::jsonb)
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order, set_type, rpe, target
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
        'set_order', set_order,
        'set_type', _set_type_name(set_type),
        'rpe', rpe,
        'target', target
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
      'superset', ie.superset,
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
  w.note,
  w.pauses,
  w.template_id,
  w.program_id,
  w.created_at,
  w.logged_by,
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
  w.note,
  w.pauses,
  w.template_id,
  w.program_id,
  w.created_at,
  w.logged_by,
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

/// The shared, read-only half of re-import enrichment, spliced into both
/// [_importWorkouts] and [_previewImport] so a dry run reports exactly what a
/// commit would do. Expects `_incoming (workout, import_id)` and
/// `_names (name, canonical, exercise_id)` ahead of it.
///
/// A re-import fills gaps and nothing else: a workout's note, an exercise's
/// note, a set's type and RPE — each only where the stored value is NULL. A
/// value already there wins, whoever wrote it, and structure (which exercises
/// and sets exist, their numbers) is never touched.
///
/// A stored set is "the same set" only by position *and* numbers: same
/// import identity, same exercise at the same order, same set order, equal
/// measurements after the insert's own casts. A set the user has since edited,
/// or one shifted by a deleted neighbour, matches nothing and is left alone —
/// which is what stops set 1's RPE landing on the old set 2.
///
/// Heart's own export names its workouts and exercises by id (`workoutId` on
/// the workout, `exercise_id` in `_names`; both NULL from every other source):
/// an exercise id is the exact match ahead of any name, and a workout id that
/// is one of the user's own workouts is that workout, already there, so the
/// file imported back into the account it came from creates nothing — and
/// fills nothing either: the store is newer than its own export, so a NULL
/// there is a clearing, not a gap.
const _reimportCandidates = '''
-- every name an exercise answers to, case-folded, one row each: its own name
-- and each alias, over the library and the user's customs. Flat so the
-- resolution below is one equi-join, not an OR over an unnest per pair
_library AS (
  SELECT id, user_id, lower(name) AS key, true AS by_name
  FROM exercises
  WHERE user_id IS NULL OR user_id = @userId
  UNION ALL
  SELECT e.id, e.user_id, lower(a), false
  FROM exercises e
  CROSS JOIN LATERAL unnest(e.aliases) a
  WHERE e.user_id IS NULL OR e.user_id = @userId
  UNION ALL
  -- the exercise an export names by id, where it is the library's or the
  -- user's own; the parser lets only a UUID through, so the cast is safe
  SELECT e.id, e.user_id, n.exercise_id, true
  FROM _names n
  JOIN exercises e ON e.id = n.exercise_id::uuid
  WHERE e.user_id IS NULL OR e.user_id = @userId
),
-- the keys an incoming name is looked up by: its id where the export gave one,
-- and two spellings — as written (an exercise the user already owns under that
-- very name, say from an import made before its translation was known) and
-- canonical (the English title behind it)
_keys AS (
  SELECT name, lower(name) AS key, 0 AS pref, false AS by_id FROM _names
  UNION ALL
  SELECT name, lower(canonical), 1, false FROM _names
  UNION ALL
  SELECT name, exercise_id, 0, true FROM _names WHERE exercise_id IS NOT NULL
),
-- keyed by the *incoming* name so downstream joins on the CSV's spelling still
-- hit; matching is case-insensitive because that is the DB's own notion of
-- identity (unique on (user_id, lower(name))). An id match is exact and wins
-- outright; by name, the user's own exercise wins over the library's, the name
-- as written over its canonical form, and a name over an alias
_resolved AS (
  SELECT DISTINCT ON (k.name) k.name, l.id
  FROM _keys k
  JOIN _library l ON l.key = k.key
  ORDER BY k.name, k.by_id DESC, l.user_id NULLS LAST, k.pref, l.by_name DESC
),
-- the stored workout an incoming one already is: imported before under the
-- same identity (by_identity, the only kind a re-import fills), or the user's
-- own workout the file was written from. Two joins, not one OR, so each is an
-- index probe
_reimported AS (
  SELECT i.import_id, w.id AS workout_id, w.note AS stored_note, i.workout, true AS by_identity
  FROM _incoming i
  JOIN workouts w ON w.user_id = @userId AND w.import_id = i.import_id
  UNION ALL
  SELECT i.import_id, w.id, w.note, i.workout, false
  FROM _incoming i
  JOIN workouts w ON w.user_id = @userId AND w.id = (i.workout->>'workoutId')::uuid
),
-- an existing workout only ever references exercises that already exist, so
-- _resolved (not the consent-gated lookup) is the whole of what can match
_reimported_exercises AS (
  SELECT r.workout_id, we.id AS workout_exercise_id, we.note AS stored_note, ex AS exercise
  FROM _reimported r
  CROSS JOIN LATERAL jsonb_array_elements(r.workout->'exercises') ex
  JOIN _resolved res ON res.name = ex->>'name'
  JOIN workout_exercises we
    ON we.workout_id = r.workout_id
   AND we.exercise_order = (ex->>'order')::int
   AND we.exercise_id = res.id
  WHERE r.by_identity
),
_fill_workouts AS (
  SELECT workout_id, workout->>'note' AS note
  FROM _reimported
  WHERE by_identity AND stored_note IS NULL AND workout->>'note' IS NOT NULL
),
_fill_exercises AS (
  SELECT workout_id, workout_exercise_id, exercise->>'note' AS note
  FROM _reimported_exercises
  WHERE stored_note IS NULL AND exercise->>'note' IS NOT NULL
),
_fill_sets AS (
  SELECT re.workout_id, es.id, _set_type_code(t.s->>'setType') AS set_type, (t.s->>'rpe')::real AS rpe
  FROM _reimported_exercises re
  CROSS JOIN LATERAL jsonb_array_elements(re.exercise->'sets') WITH ORDINALITY t(s, ordinality)
  JOIN exercise_sets es
    ON es.workout_exercise_id = re.workout_exercise_id
   AND es.set_order = (t.ordinality - 1)::int
   AND es.weight IS NOT DISTINCT FROM (t.s->>'weight')::real
   AND es.reps IS NOT DISTINCT FROM (t.s->>'reps')::int
   AND es.duration IS NOT DISTINCT FROM (t.s->>'duration')::int
   AND es.distance IS NOT DISTINCT FROM (t.s->>'distance')::real
  WHERE (es.set_type IS NULL AND t.s->>'setType' IS NOT NULL)
     OR (es.rpe IS NULL AND t.s->>'rpe' IS NOT NULL)
),
_rest_timers_in AS (
  SELECT rt->>'name' AS name, (rt->>'seconds')::int AS seconds
  FROM jsonb_array_elements(@restTimers::jsonb) rt
  WHERE (rt->>'seconds')::int > 0
)
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
/// Workouts already there ([_reimportCandidates]' `_reimported`: the same import
/// identity, or the user's own workout a Heart export names) are not inserted —
/// re-running the same export creates nothing and the report shows it — and
/// are instead *enriched*: gaps filled, nothing overwritten. ON CONFLICT DO
/// NOTHING on (user_id, import_id) still backs that for a concurrent import.
/// Rest timers become the user's per-exercise preference where they have none.
/// Ids — the workout's and its exercises'/sets' alike — are uuid-v7 minted at
/// the workout's *start* time, never the exporting store's (a Heart export's
/// ids may be another account's), because history pages by id: an import of
/// years-old workouts must land deep in pagination, not on page one, and a
/// child id shouldn't contradict its own workout's timeline.
const _importWorkouts =
    '''
WITH
_incoming AS (
  SELECT w AS workout, w->>'importId' AS import_id
  FROM jsonb_array_elements(@workouts::jsonb) w
),
-- canonical: the English title behind a title the source app writes in
-- another language (import_names), else the name itself
_names AS (
  SELECT ex->>'name' AS name, ex->>'category' AS category, ex->>'target' AS target,
         COALESCE(im.name, ex->>'name') AS canonical, ex->>'exerciseId' AS exercise_id
  FROM jsonb_array_elements(@exercises::jsonb) ex
  LEFT JOIN import_names im ON im.source = @source AND lower(im.title) = lower(ex->>'name')
),
$_reimportCandidates,
_already_imported AS (
  SELECT DISTINCT import_id FROM _reimported
),
-- a custom is created under its canonical name, so the same history exported
-- in two languages makes one custom, not two
_created_exercises AS (
  INSERT INTO exercises (name, category, target, user_id)
  -- DISTINCT ON folds case-variant spellings of one exercise into a single
  -- custom; inserting both would trip unique (user_id, lower(name))
  SELECT DISTINCT ON (lower(n.canonical)) n.canonical, n.category, n.target, @userId
  FROM _names n
  WHERE NOT exists (SELECT 1 FROM _resolved r WHERE lower(r.name) = lower(n.name))
    AND (@createCustom::jsonb IS NULL OR n.name IN (SELECT jsonb_array_elements_text(@createCustom::jsonb)))
  -- the spelling decides which row's category guess the custom gets, so the
  -- same file makes the same custom everywhere
  ORDER BY lower(n.canonical), n.canonical, n.name
  RETURNING id, name
),
-- case-folded incoming name -> exercise id; DISTINCT because two case-variant
-- incoming names resolve to the same id and must not fan out the joins below.
-- A created custom answers only to the incoming names the user approved: two
-- spellings can fold to one canonical, one approved and one declined
_lookup AS (
  SELECT DISTINCT lower(name) AS name, id
  FROM (
    SELECT name, id FROM _resolved
    UNION ALL
    SELECT n.name, c.id
    FROM _names n
    JOIN _created_exercises c ON lower(c.name) = lower(n.canonical)
    WHERE @createCustom::jsonb IS NULL OR n.name IN (SELECT jsonb_array_elements_text(@createCustom::jsonb))
  ) _all
),
_inserted_workouts AS (
  INSERT INTO workouts (id, user_id, name, started_at, completed_at, import_id, note)
  SELECT uuidv7((i.workout->>'start')::timestamptz), @userId, NULLIF(i.workout->>'name', ''), (i.workout->>'start')::timestamptz, (i.workout->>'end')::timestamptz, i.import_id, i.workout->>'note'
  FROM _incoming i
  WHERE exists (
    SELECT 1 FROM jsonb_array_elements(i.workout->'exercises') ex
    JOIN _lookup l ON l.name = lower(ex->>'name')
  )
    AND NOT exists (SELECT 1 FROM _already_imported a WHERE a.import_id = i.import_id)
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
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order, note)
  SELECT uuidv7(e.started_at), e.workout_id, l.id, e.exercise_order, e.exercise->>'note'
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
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, set_order, set_type, rpe)
  SELECT
    uuidv7(si.started_at),
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    true,
    si.set_order,
    _set_type_code(si.set_data->>'setType'),
    (si.set_data->>'rpe')::real
  FROM _sets_in si
  JOIN _inserted_exercises ie ON ie.workout_id = si.workout_id AND ie.exercise_order = si.exercise_order
  RETURNING id
),
-- the fills re-check NULL against the row as locked, so a write that landed
-- between the snapshot and this statement's update still wins
_enriched_workouts AS (
  UPDATE workouts w
  SET note = f.note
  FROM _fill_workouts f
  WHERE w.id = f.workout_id AND w.note IS NULL
  RETURNING w.id AS workout_id
),
_enriched_exercises AS (
  UPDATE workout_exercises we
  SET note = f.note
  FROM _fill_exercises f
  WHERE we.id = f.workout_exercise_id AND we.note IS NULL
  RETURNING we.workout_id
),
_enriched_sets AS (
  UPDATE exercise_sets es
  SET set_type = coalesce(es.set_type, f.set_type), rpe = coalesce(es.rpe, f.rpe)
  FROM _fill_sets f
  WHERE es.id = f.id
  RETURNING f.workout_id
),
-- only where the user has no timer of their own for the exercise. The batch
-- already folds case-variant names into one; DISTINCT ON guards the upsert,
-- which cannot touch one row twice
_rest_timers_set AS (
  INSERT INTO exercise_preferences (user_id, exercise_id, rest_timer)
  SELECT DISTINCT ON (l.id) @userId, l.id, r.seconds
  FROM _rest_timers_in r
  JOIN _lookup l ON l.name = lower(r.name)
  ORDER BY l.id, r.seconds DESC
  ON CONFLICT (user_id, exercise_id) DO UPDATE
  SET rest_timer = EXCLUDED.rest_timer
  WHERE exercise_preferences.rest_timer IS NULL
  RETURNING exercise_id
)
SELECT
  (SELECT count(*) FROM _incoming)::int AS workouts_found,
  (SELECT count(*) FROM _inserted_workouts)::int AS workouts_created,
  (SELECT count(*) FROM _inserted_sets)::int AS sets_created,
  (SELECT count(*) FROM (
     SELECT workout_id FROM _enriched_workouts
     UNION SELECT workout_id FROM _enriched_exercises
     UNION SELECT workout_id FROM _enriched_sets
   ) _any)::int AS workouts_enriched,
  (SELECT count(*) FROM _enriched_sets)::int AS sets_enriched,
  (SELECT count(*) FROM _rest_timers_set)::int AS rest_timers_set,
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
///
/// `rest_timers_set` counts an unmatched name as if the user approves it:
/// consent comes after the preview, and a declined name sets no timer.
const _previewImport =
    '''
WITH
_incoming AS (
  SELECT w AS workout, w->>'importId' AS import_id
  FROM jsonb_array_elements(@workouts::jsonb) w
),
_names AS (
  SELECT ex->>'name' AS name, COALESCE(im.name, ex->>'name') AS canonical, ex->>'exerciseId' AS exercise_id
  FROM jsonb_array_elements(@exercises::jsonb) ex
  LEFT JOIN import_names im ON im.source = @source AND lower(im.title) = lower(ex->>'name')
),
$_reimportCandidates
SELECT
  (SELECT count(*) FROM (
     SELECT workout_id FROM _fill_workouts
     UNION SELECT workout_id FROM _fill_exercises
     UNION SELECT workout_id FROM _fill_sets
   ) _any)::int AS workouts_enriched,
  (SELECT count(*) FROM _fill_sets)::int AS sets_enriched,
  (SELECT count(DISTINCT lower(r.name))
   FROM _rest_timers_in r
   WHERE NOT EXISTS (
     SELECT 1
     FROM _resolved res
     JOIN exercise_preferences ep ON ep.exercise_id = res.id AND ep.user_id = @userId
     WHERE lower(res.name) = lower(r.name) AND ep.rest_timer IS NOT NULL
   ))::int AS rest_timers_set,
  (SELECT count(DISTINCT import_id) FROM _reimported)::int AS workouts_already_imported,
  -- the *incoming* spellings that matched: the caller set-subtracts these from
  -- the batch's names, so DB-cased names would misreport case-variant matches
  COALESCE((SELECT jsonb_agg(DISTINCT name) FROM _resolved), '[]'::jsonb) AS exercises_matched
''';

/// Full replace of a workout body from `@exercises`: children the body still
/// names (by their round-tripped ids) are updated in place, new ones inserted,
/// the rest deleted — so ids round-trip rather than being re-minted, and a kept
/// row's children and comments survive the replace.
///
/// `@replacesExercises` gates that whole limb. False (the payload never
/// mentioned `exercises`) leaves `workout_exercises` and `exercise_sets`
/// untouched and answers with what the workout already has, so a shallow PUT
/// can no longer strip a session's body; true replaces, and an empty array
/// legitimately empties. See [WorkoutRequest.replacesExercises].
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
    ex->>'note' AS note,
    (ex->>'superset')::smallint AS superset,
    -- a body that leaves the superset out (a build that predates it) keeps it
    ex ? 'superset' AS sets_superset
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
-- the caller's own template and program, or nothing, as on create
_template AS (
  SELECT id FROM templates WHERE id = @templateId::uuid AND user_id = @userId
),
_program AS (
  SELECT id FROM programs WHERE id = @programId::uuid AND user_id = @userId
),
-- the note, the pauses, the template and the program are newer than most
-- clients: a body without the key keeps them, and stored pauses are cut to the
-- window the body sets
_workout AS (
  UPDATE workouts
  SET
    name = @name,
    started_at = @startedAt,
    completed_at = @completedAt,
    calories = @calories,
    note = CASE WHEN @setsNote::boolean THEN @note ELSE note END,
    template_id = CASE WHEN @setsTemplate::boolean THEN (SELECT id FROM _template) ELSE template_id END,
    program_id = CASE WHEN @setsProgram::boolean THEN (SELECT id FROM _program) ELSE program_id END,
    pauses = CASE
      WHEN @setsPauses::boolean THEN @pauses::jsonb
      ELSE _clip_pauses(pauses, @startedAt::timestamptz, @completedAt::timestamptz)
    END
  WHERE id = @workoutId::uuid AND user_id = @userId
  RETURNING id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, created_at
),
-- The body as stored, read from the statement's snapshot: every CTE sees the
-- rows as they were before this replace, whatever the others write.
_previous_exercises AS (
  SELECT we.id
  FROM workout_exercises we
  JOIN workouts w ON w.id = we.workout_id
  WHERE w.id = @workoutId::uuid AND w.user_id = @userId
),
_previous_sets AS (
  SELECT es.id
  FROM exercise_sets es
  JOIN _previous_exercises pe ON pe.id = es.workout_exercise_id
),
-- A row the body keeps is updated in place, never deleted and re-inserted
-- under its round-tripped id: the ON DELETE CASCADE of a deleted exercise
-- fires at the end of the statement, after the re-insert, and takes the
-- re-inserted row's sets (and the comments on them) with it. Only a row the
-- body no longer names is deleted, and its cascade is then the point.
_updated_exercises AS (
  UPDATE workout_exercises we
  SET
    exercise_id = el.exercise_id,
    exercise_order = otn.exercise_order,
    met = otn.met,
    note = otn.note,
    superset = CASE WHEN otn.sets_superset THEN otn.superset ELSE we.superset END
  FROM _order_to_id otn
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  WHERE @replacesExercises::boolean
    AND we.id = otn.id
    AND we.id IN (SELECT id FROM _previous_exercises)
  RETURNING we.id, we.exercise_order, we.met, we.note, we.superset
),
-- a new id, or one this workout doesn't hold: an id another workout holds
-- trips the primary key here, which the caller maps to its 400/403
_inserted_exercises AS (
  INSERT INTO workout_exercises (id, workout_id, exercise_id, exercise_order, met, note, superset)
  SELECT
    coalesce(otn.id, uuidv7(coalesce(otn.started_at, clock_timestamp()))),
    w.id,
    el.exercise_id,
    otn.exercise_order,
    otn.met,
    otn.note,
    otn.superset
  FROM _workout w
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  WHERE @replacesExercises::boolean
    AND (otn.id IS NULL OR otn.id NOT IN (SELECT id FROM _previous_exercises))
  RETURNING id, exercise_order, met, note, superset
),
_kept_exercises AS (
  SELECT id, exercise_order, met, note, superset FROM _updated_exercises
  UNION ALL
  SELECT id, exercise_order, met, note, superset FROM _inserted_exercises
),
_deleted AS (
  DELETE FROM workout_exercises
  WHERE @replacesExercises::boolean
    AND id IN (SELECT id FROM _previous_exercises)
    AND id NOT IN (SELECT id FROM _updated_exercises)
  RETURNING id
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s AS set_data,
    (t.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY t(s, ordinality)
),
_set_rows AS (
  SELECT (si.set_data->>'id')::uuid AS id, si.set_data, si.set_order, ke.id AS workout_exercise_id
  FROM _sets_input si
  JOIN _kept_exercises ke ON ke.exercise_order = si.exercise_order
),
-- set_type, rpe and target are newer than most clients: a set whose payload
-- leaves the key out (a client that doesn't know the field) keeps the stored
-- value, while an explicit null clears it
_updated_sets AS (
  UPDATE exercise_sets es
  SET
    workout_exercise_id = sr.workout_exercise_id,
    weight = (sr.set_data->>'weight')::real,
    reps = (sr.set_data->>'reps')::int,
    duration = (sr.set_data->>'duration')::int,
    distance = (sr.set_data->>'distance')::real,
    completed = COALESCE((sr.set_data->>'completed')::boolean, false),
    started_at = (sr.set_data->>'started_at')::timestamptz,
    completed_at = (sr.set_data->>'completed_at')::timestamptz,
    set_order = sr.set_order,
    set_type = CASE WHEN sr.set_data ? 'set_type' THEN _set_type_code(sr.set_data->>'set_type') ELSE es.set_type END,
    rpe = CASE WHEN sr.set_data ? 'rpe' THEN (sr.set_data->>'rpe')::real ELSE es.rpe END,
    target = CASE WHEN sr.set_data ? 'target' THEN nullif(sr.set_data->'target', 'null'::jsonb) ELSE es.target END
  FROM _set_rows sr
  WHERE es.id = sr.id AND es.id IN (SELECT id FROM _previous_sets)
  RETURNING es.id, es.workout_exercise_id, es.weight, es.reps, es.duration, es.distance, es.completed, es.started_at, es.completed_at, es.set_order, es.set_type, es.rpe, es.target
),
_inserted_sets AS (
  INSERT INTO exercise_sets (id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order, set_type, rpe, target)
  SELECT
    coalesce(sr.id, uuidv7()),
    sr.workout_exercise_id,
    (sr.set_data->>'weight')::real,
    (sr.set_data->>'reps')::int,
    (sr.set_data->>'duration')::int,
    (sr.set_data->>'distance')::real,
    COALESCE((sr.set_data->>'completed')::boolean, false),
    (sr.set_data->>'started_at')::timestamptz,
    (sr.set_data->>'completed_at')::timestamptz,
    sr.set_order,
    _set_type_code(sr.set_data->>'set_type'),
    (sr.set_data->>'rpe')::real,
    nullif(sr.set_data->'target', 'null'::jsonb)
  FROM _set_rows sr
  WHERE sr.id IS NULL OR sr.id NOT IN (SELECT id FROM _previous_sets)
  RETURNING id, workout_exercise_id, weight, reps, duration, distance, completed, started_at, completed_at, set_order, set_type, rpe, target
),
-- every stored set the body no longer names, whether its exercise stays or
-- goes; the cascade of a dropped exercise then finds nothing left
_deleted_sets AS (
  DELETE FROM exercise_sets
  WHERE @replacesExercises::boolean
    AND id IN (SELECT id FROM _previous_sets)
    AND id NOT IN (SELECT id FROM _updated_sets)
  RETURNING id
),
_written_sets AS (
  SELECT * FROM _updated_sets
  UNION ALL
  SELECT * FROM _inserted_sets
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
        'set_order', set_order,
        'set_type', _set_type_name(set_type),
        'rpe', rpe,
        'target', target
      ) ORDER BY set_order
    ) AS sets_json
  FROM _written_sets
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
      'superset', ie.superset,
      'sets', coalesce(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ie.exercise_order
  ) AS exercises_json
  FROM _kept_exercises ie
  JOIN _order_to_id otn ON otn.exercise_order = ie.exercise_order
  JOIN _exercise_lookup el ON el.exercise_id = otn.exercise_id
  JOIN exercises e ON e.id = el.exercise_id
  LEFT JOIN _sets_json sj ON sj.workout_exercise_id = ie.id
)
SELECT
  w.id, w.name, w.started_at, w.completed_at, w.calories, w.note, w.pauses, w.template_id, w.program_id, w.created_at,
  -- the replacing branch reads its own RETURNING, because a CTE cannot see
  -- rows it just wrote; the preserving branch reads the table, which is
  -- untouched in that case and so already final
  CASE
    WHEN @replacesExercises::boolean THEN coalesce(ej.exercises_json, '[]'::jsonb)
    ELSE _workout_exercises(w.id)
  END AS exercises,
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
    calories = coalesce(@calories::REAL, calories),
    -- coalesce can't clear, and the note can be cleared
    note = CASE WHEN @patchesNote::boolean THEN @note::TEXT ELSE note END,
    -- pauses the body names are checked as given; stored ones are cut to the
    -- window this patch leaves
    pauses = CASE
      WHEN @patchesPauses::boolean THEN @pauses::JSONB
      ELSE _clip_pauses(
        pauses,
        coalesce(@startedAt::TIMESTAMPTZ, started_at),
        coalesce(@completedAt::TIMESTAMPTZ, completed_at)
      )
    END
  WHERE id = @workoutId::uuid AND user_id = @userId
  RETURNING id, name, started_at, completed_at, calories, note, pauses, template_id, program_id, created_at
)
SELECT
  u.id,
  u.name,
  u.started_at,
  u.completed_at,
  u.calories,
  u.note,
  u.pauses,
  u.template_id,
  u.program_id,
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

// The workout change feed (heart-api#114): workouts that changed and
// workouts that were deleted, as one stream ordered by (transaction, id) from
// a cursor. A deletion of an id that exists again (a replayed create) is
// superseded by the workout itself.
//
// Each change carries the transaction that made it. The feed reads only
// changes from transactions older than the oldest one still running (the
// statement snapshot's xmin): every one of those has finished, so nothing
// can commit behind a cursor already handed out. A change being written
// waits for a later poll.
//
// Transaction ids belong to one cluster. A cursor at or past the snapshot's
// xmax can't have come from this one: the database was moved, and its new
// counter started lower. That cursor is stale, never read from.
const _workoutChanges = '''
WITH _check AS (
  SELECT @sinceXid::text IS NOT NULL
         AND @sinceXid::text::xid8 >= pg_snapshot_xmax(pg_current_snapshot()) AS stale
), _changes AS (
  SELECT id, changed_xid AS xid, updated_at AS at, false AS deleted
  FROM workouts
  WHERE user_id = @userId
    AND changed_xid < pg_snapshot_xmin(pg_current_snapshot())
    AND (@sinceXid::text IS NULL OR (changed_xid, id) > (@sinceXid::text::xid8, @sinceId::uuid))
  UNION ALL
  SELECT d.id, d.deleted_xid, d.deleted_at, true
  FROM archive.deleted_workouts d
  WHERE d.user_id = @userId
    AND d.deleted_xid < pg_snapshot_xmin(pg_current_snapshot())
    AND (@sinceXid::text IS NULL OR (d.deleted_xid, d.id) > (@sinceXid::text::xid8, @sinceId::uuid))
    AND NOT EXISTS (SELECT 1 FROM workouts w WHERE w.id = d.id)
), _page AS (
  SELECT id, xid, at, deleted FROM _changes ORDER BY xid, id LIMIT @limit
)
SELECT
  c.stale,
  p.id, p.xid::text AS xid, p.at, p.deleted,
  w.name, w.started_at, w.completed_at, w.calories, w.note, w.pauses, w.template_id, w.program_id, w.created_at,
  w.logged_by,
  (SELECT username FROM profiles coach WHERE coach.id = w.logged_by) AS logged_by_name,
  CASE WHEN p.deleted THEN NULL ELSE _workout_exercises(w.id) END AS exercises,
  CASE WHEN p.deleted THEN NULL ELSE COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', wi.id, 'key', wi.key, 'workout_id', wi.workout_id) ORDER BY wi.id DESC)
     FROM workout_images wi WHERE wi.workout_id = w.id),
    '[]'::jsonb
  ) END AS images
FROM _check c
LEFT JOIN _page p ON NOT c.stale
LEFT JOIN workouts w ON NOT p.deleted AND w.id = p.id
ORDER BY p.xid, p.id
''';

// Whether set `s` counts: unless the user called it invalid, when it stays in
// the log and counts for nothing. Every count of sets reads it; the anomaly
// sweep's median keeps the same rule in SQL.
const _setCounts = '''
NOT EXISTS (
  SELECT 1 FROM anomalies a WHERE a.set_id = s.id AND a.status = 'invalid'
)''';

// One exercise's sessions, newest first by workout id (ids follow start
// times, imported ones included), each with its completed working sets. The
// exercise row comes back even without sessions, so "never done" and "not
// yours" stay apart. The window bounds start times like the records'.
const _exerciseHistory =
    '''
WITH _exercise AS (
  SELECT id, name, category
  FROM exercises
  WHERE id = @exerciseId::uuid
    AND (user_id IS NULL OR user_id = @userId)
),
_sets AS (
  SELECT we.workout_id, we.exercise_order, s.set_order, s.weight, s.reps, s.duration, s.distance
  FROM workouts w
  JOIN workout_exercises we ON we.workout_id = w.id
  JOIN exercise_sets s ON s.workout_exercise_id = we.id
  WHERE w.user_id = @userId
    AND we.exercise_id = @exerciseId::uuid
    AND s.completed
    AND s.set_type IS DISTINCT FROM 'w'
    AND $_setCounts
    AND (@cursor::uuid IS NULL OR w.id < @cursor::uuid)
    AND (@from::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) >= @from::timestamptz)
    AND (@to::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) < @to::timestamptz)
),
_sessions AS (
  SELECT w.id, COALESCE(w.started_at, w.created_at) AS started_at
  FROM workouts w
  WHERE w.id IN (SELECT workout_id FROM _sets)
  ORDER BY w.id DESC
  LIMIT @limit
)
SELECT
  x.id AS exercise_id, x.name, x.category,
  ses.id AS workout_id, ses.started_at,
  s.weight, s.reps, s.duration, s.distance
FROM _exercise x
LEFT JOIN _sessions ses ON TRUE
LEFT JOIN _sets s ON s.workout_id = ses.id
ORDER BY ses.id DESC NULLS LAST, s.exercise_order, s.set_order
''';

// Every completed working set the user has done, per exercise, oldest
// workout first: the input personal records are folded from. Warm-ups are no
// one's record. The window, from inclusive and to exclusive, bounds workout
// start times, so a fold over it is the records of that span.
const _recordSets =
    '''
SELECT
  e.id AS exercise_id, e.name, e.category,
  s.weight, s.reps, s.duration, s.distance,
  w.id AS workout_id, COALESCE(w.started_at, w.created_at) AS started_at
FROM exercise_sets s
JOIN workout_exercises we ON we.id = s.workout_exercise_id
JOIN workouts w ON w.id = we.workout_id
JOIN exercises e ON e.id = we.exercise_id
WHERE w.user_id = @userId
  AND s.completed
  AND s.set_type IS DISTINCT FROM 'w'
  AND $_setCounts
  AND (@exerciseId::uuid IS NULL OR we.exercise_id = @exerciseId::uuid)
  AND (@from::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) >= @from::timestamptz)
  AND (@to::timestamptz IS NULL OR COALESCE(w.started_at, w.created_at) < @to::timestamptz)
ORDER BY e.id, COALESCE(w.started_at, w.created_at), w.id, s.set_order
''';

// Every finished workout the user started in the window, oldest first: what
// counts of workouts and the time they took are folded from. The window
// bounds start times, as the record sets' does; an unfinished workout is not
// one you have done. A duration the user called invalid still counts the
// workout, not its time.
const _workoutSpans = '''
SELECT
  id AS workout_id, COALESCE(started_at, created_at) AS started_at, completed_at, pauses,
  EXISTS (
    SELECT 1 FROM anomalies a WHERE a.workout_id = workouts.id AND a.set_id IS NULL AND a.status = 'invalid'
  ) AS time_invalid
FROM workouts
WHERE user_id = @userId
  AND completed_at IS NOT NULL
  AND (@from::timestamptz IS NULL OR COALESCE(started_at, created_at) >= @from::timestamptz)
  AND (@to::timestamptz IS NULL OR COALESCE(started_at, created_at) < @to::timestamptz)
ORDER BY COALESCE(started_at, created_at), id
''';

// OAuth (heart-api#115).
