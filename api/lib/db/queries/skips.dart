part of '../db.dart';

/// The caller's skips, newest first, a page at a time.
/// A coach's view of a student's skips: that a session was set aside and when.
/// The reason and the weather are the student's own.
const _listTargetSkips = '''
WITH
_rel AS (
  SELECT _relation(@requesterId, @targetUserId) AS r
)
SELECT id, at, NULL AS reason, NULL AS weather, template_id, program_id, false AS forbidden
FROM skips
WHERE user_id = @targetUserId
  AND (SELECT (r).scope FROM _rel) = 'coach'
  AND _readable_at((SELECT r FROM _rel), at, NULL)
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, true
FROM _rel
WHERE (r).scope IS DISTINCT FROM 'coach'
ORDER BY id DESC
LIMIT @limit
''';

const _listSkips = '''
SELECT id, at, reason, weather, template_id, program_id
FROM skips
WHERE user_id = @userId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

/// Ten years of days, and then some.
const _maxSkips = 10000;

// Idempotent on the id, as the other creates. The template and program are the
// caller's own or nothing, as on a workout: a skip always saves. An empty
// result is the cap.
const _createSkip =
    '''
WITH
_by_id AS (
  SELECT id, at, reason, weather, template_id, program_id
  FROM skips
  WHERE id = @id::uuid
    AND user_id = @userId
),
_foreign AS (
  SELECT 1
  FROM skips
  WHERE id = @id::uuid
    AND user_id <> @userId
),
_ins AS (
  INSERT INTO skips (id, user_id, at, reason, weather, template_id, program_id)
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @at::timestamptz,
    @reason,
    @weather::jsonb,
    (SELECT id FROM templates WHERE id = @templateId::uuid AND user_id = @userId),
    (SELECT id FROM programs WHERE id = @programId::uuid AND user_id = @userId)
  WHERE NOT EXISTS (SELECT 1 FROM _by_id)
    AND (
      EXISTS (SELECT 1 FROM _foreign)
      OR (SELECT count(*) FROM skips WHERE user_id = @userId) < $_maxSkips
    )
  RETURNING id, at, reason, weather, template_id, program_id
)
SELECT id, at, reason, weather, template_id, program_id, true AS created FROM _ins
UNION ALL
SELECT id, at, reason, weather, template_id, program_id, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

const _deleteSkip = '''
DELETE FROM skips
WHERE id = @id::uuid
  AND user_id = @userId
''';
