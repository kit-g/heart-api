part of '../db.dart';

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
      -- NULL is "none of its own" and falls through like name; an empty
      -- array is a translation deliberately having none
      'aliases', COALESCE(t.aliases, tb.aliases, e.aliases, '{}'),
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
) AS exercises,
-- the sync writes every served locale's glossary already resolved; a
-- regional locale without a row of its own reads its base language's
(
  SELECT g.terms
  FROM search_glossaries g
  WHERE g.locale IN (@locale, @baseLocale)
  ORDER BY g.locale = @locale DESC
  LIMIT 1
) AS glossary
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
  INSERT INTO exercises (id, name, category, target, instructions, movement, user_id)
  -- the app mints a v7 id at construction (offline-first needs identity
  -- before the server ack) and it round-trips here; absent, the column
  -- default mints one. A pattern the user gave is the movement's one group:
  -- what the library knows about a movement besides its pattern, a custom
  -- exercise doesn't say
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @name,
    @category,
    @target,
    @instructions,
    CASE WHEN @pattern::text IS NOT NULL THEN jsonb_build_object('groups', jsonb_build_array(@pattern::text)) END,
    @userId
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

/// Three outcomes, told apart without a second round trip, as a folder's
/// rename: no rows (the exercise is not the caller's own), one row with
/// `name_taken` (the rename would collide with another own exercise,
/// case-insensitively, as the create matches names), one row with the
/// exercise (updated).
const _updateExercise = '''
WITH
_target AS (
  SELECT id
  FROM exercises
  WHERE id = @exerciseId::uuid
    AND user_id = @userId
),
_conflict AS (
  SELECT 1
  FROM exercises
  WHERE user_id = @userId
    AND lower(name) = lower(@name::text)
    AND id <> @exerciseId::uuid
),
_updated AS (
  UPDATE exercises
  SET
    name = coalesce(@name::text, name),
    category = coalesce(@category, category),
    target = coalesce(@target, target),
    instructions = coalesce(@instructions, instructions),
    archived = coalesce(@archived, archived),
    -- the pattern is the movement's groups: set, or cleared, with whatever else
    -- the movement says kept; a movement left empty is none
    movement = CASE
      WHEN NOT @setsPattern::boolean THEN movement
      WHEN @pattern::text IS NOT NULL
        THEN jsonb_set(coalesce(movement, '{}'), '{groups}', jsonb_build_array(@pattern::text))
      ELSE nullif(movement - 'groups', '{}')
    END
  WHERE id = (SELECT id FROM _target)
    AND NOT EXISTS (SELECT 1 FROM _conflict)
  RETURNING id, name, category, target, instructions, asset, thumbnail, muscles, movement, health, archived,
            user_id IS NOT NULL AS own
)
SELECT
  t.id,
  u.name,
  u.category,
  u.target,
  u.instructions,
  u.asset,
  u.thumbnail,
  u.muscles,
  u.movement,
  u.health,
  u.archived,
  u.own,
  EXISTS (SELECT 1 FROM _conflict) AS name_taken
FROM _target t
LEFT JOIN _updated u ON u.id = t.id
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

/// The move lives in the database (`_move_exercise_history`, migration
/// 2026-10-10): several tables re-keyed, a conditional delete, and a dry run
/// that must report exactly what the move would do — one function, one path,
/// rather than a CTE chain here with a second read-only twin for the preview.
/// An id the caller cannot reference raises `no_data_found` with the id as the
/// detail, and source = target `invalid_parameter_value`; the mixin maps both.
const _moveExerciseHistory = '''
SELECT
  workout_exercises_moved,
  template_exercises_moved,
  preferences_moved,
  preferences_dropped,
  chart_preferences_moved,
  goals_moved,
  programs_moved,
  source_deleted
FROM _move_exercise_history(@userId, @sourceId::uuid, @targetId::uuid, @dryRun)
''';

/// A custom stops being the coach's once they are gone, as a program's copy does.
const _coachedExercises = '''
SELECT e.id, p.username AS coach_name
FROM exercises e
JOIN profiles p ON p.id = e.coach_id
WHERE e.user_id = @userId
''';
