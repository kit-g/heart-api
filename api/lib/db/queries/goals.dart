part of '../db.dart';

// Goals are visible to their owner, to a peer, and to a coach the student shared
// them with. Writing stays owner-only. A forbidden requester gets a single
// sentinel row, which the db layer turns into a 403.
const _listTargetGoals = '''
WITH
_rel AS (
  SELECT _relation(@requesterId, @targetUserId) AS r
),
_allowed AS (
  SELECT (r).scope IN ('self', 'peer') OR ((r).scope = 'coach' AND 'goals' = ANY ((r).shares)) AS allowed
  FROM _rel
),
_goals AS (
  SELECT id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at
  FROM goals
  WHERE (SELECT allowed FROM _allowed)
    AND user_id = @targetUserId::text
    AND archived = @archived::boolean
  ORDER BY created_at
)
SELECT id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at, false AS forbidden FROM _goals
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true FROM _allowed WHERE allowed IS NOT TRUE
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
  SELECT id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at
  FROM goals WHERE id = @id::uuid AND user_id = @userId
),
_foreign AS (
  SELECT 1 FROM goals WHERE id = @id::uuid AND user_id <> @userId
),
_ins AS (
  INSERT INTO goals (id, user_id, metric, exercise_id, pattern, muscle, cadence, stages)
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @metric::text,
    @exerciseId::uuid,
    @pattern::text,
    @muscle::text,
    @cadence::text,
    @stages::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM _by_id)
    AND (
      EXISTS (SELECT 1 FROM _foreign)
      OR (SELECT count(*) FROM goals WHERE user_id = @userId AND NOT archived) < $_maxActiveGoals
    )
  RETURNING id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at
)
SELECT id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at, true AS created FROM _ins
UNION ALL
SELECT id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

const _updateGoal = '''
UPDATE goals
SET metric      = @metric::text,
    exercise_id = @exerciseId::uuid,
    pattern     = @pattern::text,
    muscle      = @muscle::text,
    cadence     = @cadence::text,
    stages      = @stages::jsonb,
    archived    = @archived::boolean
WHERE id = @id::uuid
  AND user_id = @userId
RETURNING id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at
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
RETURNING id, metric, exercise_id, pattern, muscle, cadence, stages, archived, created_at
''';
