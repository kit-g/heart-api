part of '../db.dart';

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

/// The reader's standing towards a comment's target, from the workout it belongs
/// to. A coach comments only on what they can read, never on a photo, and not
/// while paused.
const _commentTargetAccess = '''
WITH
_workout AS (
  SELECT id, user_id, started_at, hidden_at
  FROM workouts
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
),
_rel AS (
  SELECT w.*, _relation(@readerId, w.user_id) AS r
  FROM _workout w
)
SELECT
  user_id AS owner_id,
  (r).scope IS NOT NULL AS related,
  (
    (r).scope IS NOT NULL
    AND (r).active
    AND _readable_at(r, started_at, hidden_at)
    AND NOT ((r).scope = 'coach' AND @targetType = 'workout_image')
  ) AS readable
FROM _rel
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
