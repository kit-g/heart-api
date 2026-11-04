part of '../db.dart';

/// With each its program: the newest of this coach's copies the student has started.
const _dirtySummaries =
    '''
SELECT s.connection_id, s.student_id, s.generation, program.*
FROM client_summaries s
JOIN connections c ON c.id = s.connection_id
LEFT JOIN LATERAL (
  SELECT $_programColumns
  FROM programs p
  WHERE p.user_id = s.student_id
    AND p.coach_id = s.coach_id
    AND NOT p.archived
    AND p.waiting_since IS NULL
  ORDER BY p.id DESC
  LIMIT 1
) program ON true
WHERE s.coach_id = @coachId
  AND s.dirty
  AND c.status IN ('active', 'paused')
LIMIT @limit
''';

/// From what the coach can read, and nothing else: a hidden or paused-over workout
/// moves none of these.
const _refreshSummary = '''
WITH
_rel AS (
  SELECT _relation(@coachId, @studentId) AS r
),
_seen AS (
  SELECT w.id, w.started_at, w.note
  FROM workouts w
  WHERE w.user_id = @studentId
    AND w.completed_at IS NOT NULL
    AND (SELECT (r).scope FROM _rel) = 'coach'
    AND _readable_at((SELECT r FROM _rel), w.started_at, w.hidden_at)
)
UPDATE client_summaries
SET
  dirty = generation IS DISTINCT FROM @generation::bigint,
  program_id = @programId::uuid,
  program_name = @programName,
  program_week = @programWeek,
  program_weeks = @programWeeks,
  ending = @ending,
  recent = coalesce(
    (SELECT array_agg(started_at ORDER BY started_at DESC) FROM _seen WHERE started_at > now() - INTERVAL '14 days'),
    '{}'
  ),
  last_trained_at = (SELECT max(started_at) FROM _seen),
  note_at = (SELECT max(started_at) FROM _seen WHERE length(trim(coalesce(note, ''))) > 0),
  lighter_at = (SELECT max(started_at) FROM _seen WHERE _workout_fell_short(id)),
  updated_at = now()
WHERE connection_id = @connectionId::uuid
RETURNING connection_id
''';

/// Reasons count only what came after the coach last looked. A gap and an ending
/// clear when they stop being true. Former clients are who and when, and no more.
const _roster = '''
WITH
_clients AS (
  SELECT
    s.connection_id,
    s.student_id,
    c.status,
    c.accepted_at,
    profile.username,
    profile.avatar_url,
    s.program_id,
    s.program_name,
    s.program_week,
    s.program_weeks,
    s.recent,
    s.last_trained_at,
    array_remove(
      ARRAY[
        CASE WHEN s.lighter_at > coalesce(s.reviewed_at, '-infinity') THEN 'lighter' END,
        CASE WHEN s.note_at > coalesce(s.reviewed_at, '-infinity') THEN 'note' END,
        CASE
          WHEN c.status = 'active'
            AND coalesce(s.last_trained_at, c.accepted_at) < now() - INTERVAL '7 days'
          THEN 'gap'
        END,
        CASE WHEN s.ending THEN 'ending' END
      ],
      NULL
    ) AS reasons
  FROM client_summaries s
  JOIN connections c ON c.id = s.connection_id
  JOIN profiles profile ON profile.id = s.student_id
  WHERE s.coach_id = @coachId
    AND (
      (@former::boolean AND c.status IN ('severed', 'blocked'))
      OR (NOT @former::boolean AND c.status IN ('active', 'paused'))
    )
),
_ranked AS (
  SELECT
    *,
    CASE WHEN NOT @former::boolean AND cardinality(reasons) = 0 THEN 1 ELSE 0 END AS rank
  FROM _clients
  WHERE @reason::text IS NULL OR @reason = ANY (reasons)
)
SELECT
  connection_id,
  student_id,
  status,
  accepted_at,
  username,
  avatar_url,
  CASE WHEN @former::boolean THEN NULL ELSE program_id END AS program_id,
  CASE WHEN @former::boolean THEN NULL ELSE program_name END AS program_name,
  CASE WHEN @former::boolean THEN NULL ELSE program_week END AS program_week,
  CASE WHEN @former::boolean THEN NULL ELSE program_weeks END AS program_weeks,
  CASE WHEN @former::boolean THEN '{}'::timestamptz[] ELSE recent END AS recent,
  CASE WHEN @former::boolean THEN NULL ELSE last_trained_at END AS last_trained_at,
  CASE WHEN @former::boolean THEN '{}'::text[] ELSE reasons END AS reasons
FROM _ranked
WHERE @afterRank::int IS NULL OR (rank, connection_id) > (@afterRank::int, @afterId::uuid)
ORDER BY rank, connection_id
LIMIT @limit
''';

const _markReviewed = '''
UPDATE client_summaries
SET reviewed_at = least(coalesce(@at::timestamptz, now()), now())
WHERE connection_id = @connectionId::uuid
  AND coach_id = @coachId
RETURNING connection_id
''';

const _coachFeed = '''
WITH
_clients AS (
  SELECT s.student_id, s.program_id, s.program_name, s.ending, s.updated_at, _relation(@coachId, s.student_id) AS r
  FROM client_summaries s
  JOIN connections c ON c.id = s.connection_id
  WHERE s.coach_id = @coachId
    AND c.status IN ('active', 'paused')
),
_items AS (
  SELECT 'workout' AS kind, w.id::text AS id, w.user_id AS student_id, w.completed_at AS at, w.name AS title
  FROM _clients c
  JOIN workouts w ON w.user_id = c.student_id
  WHERE w.completed_at IS NOT NULL
    AND (c.r).scope = 'coach'
    AND _readable_at(c.r, w.started_at, w.hidden_at)
  UNION ALL
  SELECT 'skip', k.id::text, k.user_id, k.at, NULL
  FROM _clients c
  JOIN skips k ON k.user_id = c.student_id
  WHERE (c.r).scope = 'coach'
    AND _readable_at(c.r, k.at, NULL)
  UNION ALL
  SELECT 'ending', c.program_id::text, c.student_id, c.updated_at, c.program_name
  FROM _clients c
  WHERE c.ending
    AND c.program_id IS NOT NULL
)
SELECT i.kind, i.id, i.student_id, i.at, i.title, p.username, p.avatar_url
FROM _items i
JOIN profiles p ON p.id = i.student_id
WHERE @afterAt::timestamptz IS NULL OR (i.at, i.id) < (@afterAt::timestamptz, @afterId::text)
ORDER BY i.at DESC, i.id DESC
LIMIT @limit
''';
