part of '../db.dart';

/// Empty when the library is full; a row saying `taken` when the id is another
/// coach's. Saving what's already the current version, as a retried save does,
/// answers that version rather than making an identical one.
const _saveCoachProgram =
    '''
WITH
_count AS (
  SELECT count(*) AS n FROM library_programs WHERE coach_id = @coachId
),
_same AS (
  SELECT l.id, l.name, l.version, l.updated_at, v.body
  FROM library_programs l
  JOIN library_program_versions v ON v.library_program_id = l.id AND v.version = l.version
  WHERE l.id = @id::uuid
    AND l.coach_id = @coachId
    AND l.name = @name
    AND v.body = @body::jsonb
),
_saved AS (
  INSERT INTO library_programs (id, coach_id, name)
  SELECT @id::uuid, @coachId, @name
  FROM _count
  WHERE NOT EXISTS (SELECT 1 FROM _same)
    AND (
      n < $_maxCoachPrograms
      OR EXISTS (SELECT 1 FROM library_programs WHERE id = @id::uuid AND coach_id = @coachId)
    )
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name, version = library_programs.version + 1, updated_at = now()
  WHERE library_programs.coach_id = EXCLUDED.coach_id
  RETURNING id, name, version, updated_at
),
_version AS (
  INSERT INTO library_program_versions (library_program_id, version, body)
  SELECT id, version, @body::jsonb
  FROM _saved
  RETURNING body
)
SELECT s.id, s.name, s.version, s.updated_at, v.body, false AS taken
FROM _saved s, _version v
UNION ALL
SELECT id, name, version, updated_at, body, false
FROM _same
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, true
FROM library_programs
WHERE id = @id::uuid
  AND coach_id <> @coachId
''';

const _listCoachPrograms = '''
SELECT id, name, version, updated_at
FROM library_programs
WHERE coach_id = @coachId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _getCoachProgram = '''
SELECT l.id, l.name, l.version, l.updated_at, v.body
FROM library_programs l
JOIN library_program_versions v ON v.library_program_id = l.id AND v.version = l.version
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
''';

const _deleteCoachProgram = '''
DELETE FROM library_programs
WHERE id = @id::uuid
  AND coach_id = @coachId
RETURNING id
''';

/// Who holds a copy, of those the coach still reads as a coach: what ended or is
/// under a block isn't theirs to see.
const _listCoachProgramHolders = '''
SELECT
  p.connection_id,
  p.user_id AS student_id,
  profile.username,
  profile.avatar_url,
  p.id AS program_id,
  p.library_version
FROM programs p
JOIN library_programs l ON l.id = p.library_program_id
JOIN profiles profile ON profile.id = p.user_id
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
  AND p.coach_id = @coachId
  AND p.connection_id IS NOT NULL
  AND (_relation(@coachId, p.user_id)).scope IS NOT DISTINCT FROM 'coach'
ORDER BY profile.username
''';

/// A student is who's across an active coach row from this coach, under no block.
const _coachSendContext = '''
SELECT
  l.version,
  v.body,
  c.student_id,
  existing.id AS existing_id,
  existing.library_version AS existing_version,
  EXISTS (
    SELECT 1
    FROM programs p
    WHERE p.user_id = c.student_id
      AND NOT p.archived
  ) AS on_something
FROM library_programs l
JOIN library_program_versions v ON v.library_program_id = l.id AND v.version = l.version
LEFT JOIN LATERAL (
  SELECT
    CASE WHEN x.initiator_id = @coachId THEN x.target_id ELSE x.initiator_id END AS student_id
  FROM connections x
  WHERE x.id = @connectionId::uuid
    AND x.status = 'active'
    AND (
      (x.initiator_id = @coachId AND x.initiator_role = 'COACH')
      OR (x.target_id = @coachId AND x.target_role = 'COACH')
    )
    AND NOT _blocked_between(x.initiator_id, x.target_id)
) c ON true
LEFT JOIN programs existing ON existing.user_id = c.student_id AND existing.library_program_id = l.id
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
''';

/// Any exercise the body names, as the one the student has: the one an earlier send
/// chose (@known) while they still have it, so a rename keeps it, then their own by
/// that name, then the library's, and otherwise a copy made for them. A name matches
/// whatever its case, as an import's does, and the same spelling wins a tie. An id that
/// isn't an exercise, such as a session's, finds no row and stays out of the answer.
/// So does someone else's private exercise: a coach can pass on only what they can see.
const _matchExercisesForStudent = '''
WITH
_sources AS (
  SELECT e.*
  FROM exercises e
  WHERE e.id = ANY (@ids::uuid[])
    AND (e.user_id IS NULL OR e.user_id = @coachId)
),
_matched AS (
  SELECT
    s.id AS source_id,
    s.name,
    coalesce(
      (
        SELECT k.id FROM exercises k
        WHERE k.id = (@known::jsonb ->> s.id::text)::uuid
          AND (k.user_id IS NULL OR k.user_id = @studentId)
      ),
      (
        SELECT e2.id FROM exercises e2
        WHERE lower(e2.name) = lower(s.name)
          AND (e2.user_id IS NULL OR e2.user_id = @studentId)
        ORDER BY e2.user_id NULLS LAST, e2.name = s.name DESC, e2.id
        LIMIT 1
      )
    ) AS resolved_id
  FROM _sources s
),
_copied AS (
  INSERT INTO exercises (
    name, category, target, instructions, asset, thumbnail, muscles, movement, health, user_id, coach_id
  )
  SELECT DISTINCT ON (s.name)
    s.name, s.category, s.target, s.instructions, s.asset, s.thumbnail, s.muscles, s.movement, s.health, @studentId,
    @coachId
  FROM _sources s
  JOIN _matched m ON m.source_id = s.id
  WHERE m.resolved_id IS NULL
  RETURNING id, name
)
SELECT m.source_id, coalesce(m.resolved_id, c.id) AS exercise_id
FROM _matched m
LEFT JOIN _copied c ON c.name = m.name AND m.resolved_id IS NULL
''';

const _invitationProgram = '''
SELECT library_program_id FROM invitations WHERE token_hash = @tokenHash
''';

const _attachInvitationProgram = '''
UPDATE invitations i
SET library_program_id = l.id
FROM library_programs l
WHERE i.id = @invitationId::uuid
  AND i.inviter_id = @coachId
  AND l.id = @programId::uuid
  AND l.coach_id = @coachId
RETURNING i.id
''';

const _startProgram = '''
UPDATE programs
SET waiting_since = NULL
WHERE id = @programId::uuid
  AND user_id = @userId
RETURNING id
''';
