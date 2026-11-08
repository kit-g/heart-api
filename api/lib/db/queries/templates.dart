part of '../db.dart';

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
    (ex->>'id')::uuid AS id,
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id,
    (ex->>'rest')::int AS rest,
    -- a body that leaves rest or superset out (a build that predates it) keeps
    -- the stored one
    ex ? 'rest' AS sets_rest,
    (ex->>'superset')::smallint AS superset,
    ex ? 'superset' AS sets_superset,
    ex->>'pattern' AS pattern,
    ex ? 'pattern' AS sets_pattern,
    nullif(ex->'totalReps', 'null'::jsonb) AS total_reps,
    ex ? 'totalReps' AS sets_total_reps
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
  INSERT INTO templates (id, user_id, name, order_index, folder_id, program_id, joined_program_at, note)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @name, @orderIndex, (SELECT id FROM _folder), @programId::uuid, @joined::timestamptz, @note
  WHERE NOT EXISTS (SELECT 1 FROM _existing_template)
    AND (
      EXISTS (SELECT 1 FROM _foreign_template)
      OR (@folderId::uuid IS NULL OR EXISTS (SELECT 1 FROM _folder))
    )
  RETURNING id, name, order_index, folder_id, source_template_id, assigned_by, sync_enabled, created_at, program_id, joined_program_at, note
),
-- ids round-trip, except one another row already holds: a template saved
-- from a workout carries the workout's ids, and saving it twice must not
-- collide, so that row gets a fresh id instead
_inserted_exercises AS (
  INSERT INTO template_exercises (id, template_id, exercise_id, exercise_order, rest, superset, pattern, total_reps)
  SELECT
    CASE
      WHEN otn.id IS NULL OR EXISTS (SELECT 1 FROM template_exercises x WHERE x.id = otn.id) THEN uuidv7()
      ELSE otn.id
    END,
    t.id,
    el.id,
    otn.exercise_order,
    otn.rest,
    otn.superset,
    otn.pattern,
    otn.total_reps
  FROM _template t
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.id = otn.exercise_id
  RETURNING id, exercise_id, exercise_order, rest, superset, pattern, total_reps
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
  INSERT INTO template_exercise_sets (id, template_exercise_id, weight, reps, duration, distance, set_order, set_type, target)
  SELECT
    CASE
      WHEN (si.set_data->>'id') IS NULL
        OR EXISTS (SELECT 1 FROM template_exercise_sets x WHERE x.id = (si.set_data->>'id')::uuid)
        THEN uuidv7()
      ELSE (si.set_data->>'id')::uuid
    END,
    ie.id,
    (si.set_data->>'weight')::real,
    (si.set_data->>'reps')::int,
    (si.set_data->>'duration')::int,
    (si.set_data->>'distance')::real,
    si.set_order,
    _set_type_code(si.set_data->>'set_type'),
    nullif(si.set_data->'target', 'null'::jsonb)
  FROM _sets_input si
  JOIN _inserted_exercises ie ON ie.exercise_order = si.exercise_order
  RETURNING id, template_exercise_id, weight, reps, duration, distance, set_order, set_type, target
),
_sets_json AS (
  SELECT
    template_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 'weight', weight, 'reps', reps,
        'duration', duration, 'distance', distance, 'set_order', set_order,
        'set_type', _set_type_name(set_type), 'target', target
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
      'rest', ie.rest,
      'superset', ie.superset,
      'pattern', ie.pattern,
      'totalReps', ie.total_reps,
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
  t.program_id,
  t.joined_program_at,
  t.note,
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
  t.program_id,
  t.joined_program_at,
  t.note,
  _template_exercises(t.id) AS exercises,
  false AS created
FROM templates t
LEFT JOIN template_folders f ON f.id = t.folder_id
LEFT JOIN profiles p ON p.id = t.assigned_by
WHERE t.id IN (SELECT id FROM _existing_template)
''';

/// Full replace of a template body from `@exercises`, the way `_replaceWorkout`
/// replaces a workout's: rows the body still names by their round-tripped ids
/// are updated in place, new ones inserted, the rest deleted.
const _replaceTemplate = '''
WITH
_folder AS (
  SELECT id FROM template_folders
  WHERE id = @folderId::uuid AND user_id = @userId
),
_order_to_id AS (
  SELECT
    (ex->>'id')::uuid AS id,
    (ex->>'order')::int AS exercise_order,
    (ex->>'exercise_id')::uuid AS exercise_id,
    (ex->>'rest')::int AS rest,
    -- a body that leaves rest or superset out (a build that predates it) keeps
    -- the stored one
    ex ? 'rest' AS sets_rest,
    (ex->>'superset')::smallint AS superset,
    ex ? 'superset' AS sets_superset,
    ex->>'pattern' AS pattern,
    ex ? 'pattern' AS sets_pattern,
    nullif(ex->'totalReps', 'null'::jsonb) AS total_reps,
    ex ? 'totalReps' AS sets_total_reps
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
-- @movesProgram and @changesNote do the same for the program and the note: a
-- body from a build that predates them keeps what is stored. A program the user
-- does not own trips templates_program_fk.
_template AS (
  UPDATE templates
  SET name = @name,
      order_index = @orderIndex,
      folder_id = CASE WHEN @movesFolder::boolean THEN (SELECT id FROM _folder) ELSE folder_id END,
      program_id = CASE WHEN @movesProgram::boolean THEN @programId::uuid ELSE program_id END,
      joined_program_at = CASE
          WHEN @movesProgram::boolean AND @joined::timestamptz IS NOT NULL THEN @joined::timestamptz
          ELSE joined_program_at
        END,
      note = CASE WHEN @changesNote::boolean THEN @note ELSE note END
  WHERE id = @templateId::uuid AND user_id = @userId
    AND (NOT @movesFolder::boolean OR @folderId::uuid IS NULL OR EXISTS (SELECT 1 FROM _folder))
  RETURNING id, name, order_index, folder_id, source_template_id, assigned_by, sync_enabled, created_at, program_id, joined_program_at, note
),
-- The body as stored, read from the statement's snapshot. Empty unless the
-- template update above matched, so a refused folder move writes nothing.
_previous_exercises AS (
  SELECT te.id
  FROM template_exercises te
  JOIN _template t ON t.id = te.template_id
),
_previous_sets AS (
  SELECT tes.id
  FROM template_exercise_sets tes
  JOIN _previous_exercises pe ON pe.id = tes.template_exercise_id
),
-- A kept row is updated in place, never deleted and re-inserted under its id:
-- the ON DELETE CASCADE of a deleted exercise fires at the end of the
-- statement and would take the re-inserted sets with it.
_updated_exercises AS (
  UPDATE template_exercises te
  SET
    exercise_id = el.id,
    exercise_order = otn.exercise_order,
    rest = CASE WHEN otn.sets_rest THEN otn.rest ELSE te.rest END,
    superset = CASE WHEN otn.sets_superset THEN otn.superset ELSE te.superset END,
    pattern = CASE WHEN otn.sets_pattern THEN otn.pattern ELSE te.pattern END,
    total_reps = CASE WHEN otn.sets_total_reps THEN otn.total_reps ELSE te.total_reps END
  FROM _order_to_id otn
  JOIN _exercise_lookup el ON el.id = otn.exercise_id
  WHERE te.id = otn.id AND te.id IN (SELECT id FROM _previous_exercises)
  RETURNING te.id, te.exercise_id, te.exercise_order, te.rest, te.superset, te.pattern, te.total_reps
),
-- an id another template holds gets a fresh one, as on create
_inserted_exercises AS (
  INSERT INTO template_exercises (id, template_id, exercise_id, exercise_order, rest, superset, pattern, total_reps)
  SELECT
    CASE
      WHEN otn.id IS NULL OR EXISTS (SELECT 1 FROM template_exercises x WHERE x.id = otn.id) THEN uuidv7()
      ELSE otn.id
    END,
    t.id,
    el.id,
    otn.exercise_order,
    otn.rest,
    otn.superset,
    otn.pattern,
    otn.total_reps
  FROM _template t
  CROSS JOIN _order_to_id otn
  JOIN _exercise_lookup el ON el.id = otn.exercise_id
  WHERE otn.id IS NULL OR otn.id NOT IN (SELECT id FROM _previous_exercises)
  RETURNING id, exercise_id, exercise_order, rest, superset, pattern, total_reps
),
_kept_exercises AS (
  SELECT id, exercise_id, exercise_order, rest, superset, pattern, total_reps FROM _updated_exercises
  UNION ALL
  SELECT id, exercise_id, exercise_order, rest, superset, pattern, total_reps FROM _inserted_exercises
),
_deleted AS (
  DELETE FROM template_exercises
  WHERE id IN (SELECT id FROM _previous_exercises)
    AND id NOT IN (SELECT id FROM _updated_exercises)
  RETURNING id
),
_sets_input AS (
  SELECT
    (ex->>'order')::int AS exercise_order,
    s AS set_data,
    (ord.ordinality - 1)::int AS set_order
  FROM jsonb_array_elements(@exercises::jsonb) ex,
  LATERAL jsonb_array_elements(ex->'sets') WITH ORDINALITY ord(s, ordinality)
),
_set_rows AS (
  SELECT (si.set_data->>'id')::uuid AS id, si.set_data, si.set_order, ke.id AS template_exercise_id
  FROM _sets_input si
  JOIN _kept_exercises ke ON ke.exercise_order = si.exercise_order
),
-- a set whose payload leaves set_type or target out (a client that doesn't
-- know the field) keeps the stored value; an explicit one, normal and null
-- included, sets it
_updated_sets AS (
  UPDATE template_exercise_sets tes
  SET
    template_exercise_id = sr.template_exercise_id,
    weight = (sr.set_data->>'weight')::real,
    reps = (sr.set_data->>'reps')::int,
    duration = (sr.set_data->>'duration')::int,
    distance = (sr.set_data->>'distance')::real,
    set_order = sr.set_order,
    set_type = CASE WHEN sr.set_data ? 'set_type' THEN _set_type_code(sr.set_data->>'set_type') ELSE tes.set_type END,
    target = CASE WHEN sr.set_data ? 'target' THEN nullif(sr.set_data->'target', 'null'::jsonb) ELSE tes.target END
  FROM _set_rows sr
  WHERE tes.id = sr.id AND tes.id IN (SELECT id FROM _previous_sets)
  RETURNING tes.id, tes.template_exercise_id, tes.weight, tes.reps, tes.duration, tes.distance, tes.set_order, tes.set_type, tes.target
),
_inserted_sets AS (
  INSERT INTO template_exercise_sets (id, template_exercise_id, weight, reps, duration, distance, set_order, set_type, target)
  SELECT
    CASE
      WHEN sr.id IS NULL OR EXISTS (SELECT 1 FROM template_exercise_sets x WHERE x.id = sr.id) THEN uuidv7()
      ELSE sr.id
    END,
    sr.template_exercise_id,
    (sr.set_data->>'weight')::real,
    (sr.set_data->>'reps')::int,
    (sr.set_data->>'duration')::int,
    (sr.set_data->>'distance')::real,
    sr.set_order,
    _set_type_code(sr.set_data->>'set_type'),
    nullif(sr.set_data->'target', 'null'::jsonb)
  FROM _set_rows sr
  WHERE sr.id IS NULL OR sr.id NOT IN (SELECT id FROM _previous_sets)
  RETURNING id, template_exercise_id, weight, reps, duration, distance, set_order, set_type, target
),
-- every stored set the body no longer names, whether its exercise stays or goes
_deleted_sets AS (
  DELETE FROM template_exercise_sets
  WHERE id IN (SELECT id FROM _previous_sets)
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
    template_exercise_id,
    jsonb_agg(
      jsonb_build_object(
        'id', id, 'weight', weight, 'reps', reps,
        'duration', duration, 'distance', distance, 'set_order', set_order,
        'set_type', _set_type_name(set_type), 'target', target
      ) ORDER BY set_order
    ) AS sets_json
  FROM _written_sets
  GROUP BY template_exercise_id
),
_exercises_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', ke.id,
      'exercise', jsonb_build_object('id', el.id, 'name', el.name, 'category', el.category, 'target', el.target),
      'exercise_order', ke.exercise_order,
      'rest', ke.rest,
      'superset', ke.superset,
      'pattern', ke.pattern,
      'totalReps', ke.total_reps,
      'sets', COALESCE(sj.sets_json, '[]'::jsonb)
    ) ORDER BY ke.exercise_order
  ) AS exercises_json
  FROM _kept_exercises ke
  JOIN _exercise_lookup el ON el.id = ke.exercise_id
  LEFT JOIN _sets_json sj ON sj.template_exercise_id = ke.id
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
  t.program_id,
  t.joined_program_at,
  t.note,
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
  t.program_id,
  t.joined_program_at,
  t.note,
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
  t.program_id,
  t.joined_program_at,
  t.note,
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
-- The connection has to be live. A pending request, a declined one, a severed,
-- blocked or paused relationship is not a licence to push templates into
-- someone's library.
_allowed AS (
  SELECT 1
  FROM (SELECT _relation(@coachId, @studentId) AS r) rel
  WHERE (r).scope IN ('coach', 'peer')
    AND (r).active
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
    te.rest,
    te.superset,
    te.pattern,
    te.total_reps,
    e.name, e.category, e.target, e.instructions, e.asset, e.thumbnail, e.muscles, e.movement, e.health,
    (
      SELECT e2.id FROM exercises e2
      WHERE lower(e2.name) = lower(e.name)
        AND (e2.user_id IS NULL OR e2.user_id = @studentId)
      ORDER BY e2.user_id NULLS LAST, e2.name = e.name DESC, e2.id
      LIMIT 1
    ) AS resolved_id
  FROM template_exercises te
  JOIN exercises e ON e.id = te.exercise_id
  WHERE te.template_id IN (SELECT id FROM _to_share)
),
-- Copy any unresolved exercises into the student's library so the FK holds.
-- DISTINCT ON dedupes across masters that name the same missing exercise.
_copied_exercises AS (
  INSERT INTO exercises (
    name, category, target, instructions, asset, thumbnail, muscles, movement, health, user_id, coach_id
  )
  SELECT DISTINCT ON (lower(name))
    name, category, target, instructions, asset, thumbnail, muscles, movement, health, @studentId, @coachId
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
    me.rest,
    me.superset,
    me.pattern,
    me.total_reps,
    coalesce(me.resolved_id, c.id) AS exercise_id
  FROM _master_exercises me
  LEFT JOIN _copied_exercises c ON lower(c.name) = lower(me.name) AND me.resolved_id IS NULL
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
  INSERT INTO template_exercises (template_id, exercise_id, exercise_order, rest, superset, pattern, total_reps)
  SELECT nt.id, re.exercise_id, re.exercise_order, re.rest, re.superset, re.pattern, re.total_reps
  FROM _new_template nt
  JOIN _resolved_exercises re ON re.master_id = nt.source_template_id
  RETURNING id, template_id, exercise_order
),
_new_sets AS (
  INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, duration, distance, set_order, set_type, target)
  SELECT ne.id, tes.weight, tes.reps, tes.duration, tes.distance, tes.set_order, tes.set_type, tes.target
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
