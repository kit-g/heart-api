part of '../db.dart';

/// Which of a reaction's target columns [target] names, for a WHERE on one.
const _reactionOnTarget = '''
CASE @targetType
  WHEN 'workout' THEN r.workout_id = @targetId::uuid
  WHEN 'workout_exercise' THEN r.workout_exercise_id = @targetId::uuid
  WHEN 'exercise_set' THEN r.exercise_set_id = @targetId::uuid
  WHEN 'workout_image' THEN r.workout_image_id = @targetId::uuid
END''';

const _reactionColumns = '''
r.id,
r.author_id,
(SELECT p.username FROM profiles p WHERE p.id = r.author_id) AS author_name,
r.kind,
r.created_at,
coalesce(r.workout_id, r.workout_exercise_id, r.exercise_set_id, r.workout_image_id) AS target_id,
CASE
  WHEN r.workout_id IS NOT NULL THEN 'workout'
  WHEN r.workout_exercise_id IS NOT NULL THEN 'workout_exercise'
  WHEN r.exercise_set_id IS NOT NULL THEN 'exercise_set'
  WHEN r.workout_image_id IS NOT NULL THEN 'workout_image'
END AS target_type''';

/// A changed word keeps when the reaction was first left, and `created` says
/// whether this statement made the row. No row when the target doesn't exist,
/// or when another request of the same person's is writing it at once: the
/// insert waited for theirs, and the update can't see a row committed after
/// the statement began.
const _setReaction =
    '''
WITH
_written AS (
  INSERT INTO reactions (author_id, kind, workout_id, workout_exercise_id, exercise_set_id, workout_image_id)
  SELECT
    @authorId,
    @kind,
    CASE WHEN @targetType = 'workout' THEN @targetId::uuid END,
    CASE WHEN @targetType = 'workout_exercise' THEN @targetId::uuid END,
    CASE WHEN @targetType = 'exercise_set' THEN @targetId::uuid END,
    CASE WHEN @targetType = 'workout_image' THEN @targetId::uuid END
  WHERE ($_commentTargetWorkout) IS NOT NULL
  ON CONFLICT DO NOTHING
  RETURNING *
),
_changed AS (
  UPDATE reactions r
  SET kind = @kind
  WHERE r.author_id = @authorId
    AND ($_reactionOnTarget)
    AND NOT EXISTS (SELECT 1 FROM _written)
  RETURNING r.*
),
_one AS (
  SELECT *, true AS created FROM _written
  UNION ALL
  SELECT *, false FROM _changed
)
SELECT $_reactionColumns, r.created
FROM _one r
''';

const _removeReaction =
    '''
DELETE FROM reactions r
WHERE r.author_id = @authorId
  AND ($_reactionOnTarget)
''';

const _listReactions =
    '''
SELECT $_reactionColumns
FROM reactions r
WHERE ($_reactionOnTarget)
  AND (@cursor::uuid IS NULL OR r.id < @cursor::uuid)
ORDER BY r.id DESC
LIMIT @limit
''';

const _summarizeReactions =
    '''
SELECT
  coalesce(jsonb_object_agg(kind, n) FILTER (WHERE kind IS NOT NULL), '{}'::jsonb) AS counts,
  (
    SELECT r.kind FROM reactions r
    WHERE r.author_id = @readerId
      AND ($_reactionOnTarget)
  ) AS mine
FROM (
  SELECT r.kind, count(*) AS n
  FROM reactions r
  WHERE ($_reactionOnTarget)
  GROUP BY r.kind
) k
''';
