part of '../db.dart';

/// With each its program: the newest of this coach's copies the student has started.
/// All of them, so no client is read from a summary never worked out.
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
''';

/// From what the coach can read, and nothing else: a hidden or paused-over workout
/// moves none of these. A reason is dated when it reached the server, not when the
/// workout started, so one that syncs after the coach looked still counts: a note by
/// the workout's last change, falling short by that or its plan's arrival. A workout
/// the coach logged themselves raises neither: they were there.
const _refreshSummary = '''
WITH
_rel AS (
  SELECT _relation(@coachId, @studentId) AS r
),
_seen AS (
  SELECT w.id, w.started_at, w.updated_at, w.note, w.logged_by IS NOT DISTINCT FROM @coachId AS by_coach
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
  -- an ending keeps the date it began, so the feed doesn't move it
  ending_since = CASE WHEN @ending::boolean THEN coalesce(ending_since, now()) END,
  recent = coalesce(
    (SELECT array_agg(started_at ORDER BY started_at DESC) FROM _seen WHERE started_at > now() - INTERVAL '14 days'),
    '{}'
  ),
  last_trained_at = (SELECT max(started_at) FROM _seen),
  note_at = (SELECT max(updated_at) FROM _seen WHERE NOT by_coach AND length(trim(coalesce(note, ''))) > 0),
  -- only a workout with a plan can fall short, so only those are compared
  lighter_at = (
    SELECT max(greatest(s.updated_at, p.created_at))
    FROM _seen s
    JOIN workout_plans p ON p.workout_id = s.id
    WHERE NOT s.by_coach
      AND _workout_fell_short(s.id)
  ),
  updated_at = now()
WHERE connection_id = @connectionId::uuid
RETURNING connection_id
''';

/// Reasons count only what came after the coach last looked. A gap and an ending
/// clear when they stop being true, and a gap counts from the last of training,
/// accepting and resuming. Former clients are who and when, and no more, so a reason
/// doesn't filter them, and someone under a block isn't one: a block reads as no such
/// person, and a lifted one as an ending.
const _roster = '''
WITH
_clients AS (
  SELECT
    s.connection_id,
    s.student_id,
    CASE WHEN c.status = 'blocked' THEN 'severed' ELSE c.status END AS status,
    c.accepted_at,
    profile.username,
    profile.avatar_url,
    s.program_id,
    s.program_name,
    s.program_week,
    s.program_weeks,
    -- a summary nobody has marked since keeps times that have aged out
    ARRAY(SELECT t FROM unnest(s.recent) t WHERE t > now() - INTERVAL '14 days' ORDER BY t DESC) AS recent,
    s.last_trained_at,
    array_remove(
      ARRAY[
        CASE WHEN s.lighter_at > coalesce(s.reviewed_at, '-infinity') THEN 'lighter' END,
        CASE WHEN s.note_at > coalesce(s.reviewed_at, '-infinity') THEN 'note' END,
        CASE
          WHEN c.status = 'active'
            AND greatest(
              s.last_trained_at,
              c.accepted_at,
              -- the last resume: back to active after a pause
              (
                SELECT max(e.at)
                FROM connection_events e
                WHERE e.connection_id = c.id
                  AND e.status = 'active'
                  AND EXISTS (
                    SELECT 1
                    FROM connection_events paused
                    WHERE paused.connection_id = c.id
                      AND paused.status = 'paused'
                      AND paused.at <= e.at
                  )
              )
            ) < now() - INTERVAL '7 days'
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
      (@former::boolean AND c.status IN ('severed', 'blocked') AND NOT _blocked_between(@coachId, s.student_id))
      OR (NOT @former::boolean AND c.status IN ('active', 'paused'))
    )
),
_ranked AS (
  SELECT
    *,
    CASE WHEN NOT @former::boolean AND cardinality(reasons) = 0 THEN 1 ELSE 0 END AS rank
  FROM _clients
  WHERE @former::boolean
    OR @reason::text IS NULL
    OR @reason = ANY (reasons)
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
-- only forward: a look that arrives late doesn't bring back what a later one cleared
SET reviewed_at = greatest(reviewed_at, least(coalesce(@at::timestamptz, now()), now()))
WHERE connection_id = @connectionId::uuid
  AND coach_id = @coachId
RETURNING connection_id
''';

/// A student coached in two domains has two summaries, and is one reader's client
/// once. Each kind takes its own page before they're merged, so a page reads no more
/// of a client's history than it shows.
const _coachFeed = '''
WITH
_summaries AS (
  SELECT s.student_id, s.program_id, s.program_name, s.ending_since
  FROM client_summaries s
  JOIN connections c ON c.id = s.connection_id
  WHERE s.coach_id = @coachId
    AND c.status IN ('active', 'paused')
),
_clients AS (
  SELECT student_id, _relation(@coachId, student_id) AS r
  FROM (SELECT DISTINCT student_id FROM _summaries) students
),
_items AS (
  (
    SELECT 'workout' AS kind, w.id::text AS id, w.user_id AS student_id, w.completed_at AS at, w.name AS title
    FROM _clients c
    JOIN workouts w ON w.user_id = c.student_id
    WHERE w.completed_at IS NOT NULL
      AND (c.r).scope = 'coach'
      AND (@afterAt::timestamptz IS NULL OR (w.completed_at, w.id::text) < (@afterAt::timestamptz, @afterId::text))
      AND _readable_at(c.r, w.started_at, w.hidden_at)
    ORDER BY at DESC, id DESC
    LIMIT @limit
  )
  UNION ALL
  (
    SELECT 'skip', k.id::text, k.user_id, k.at, NULL
    FROM _clients c
    JOIN skips k ON k.user_id = c.student_id
    WHERE (c.r).scope = 'coach'
      AND (@afterAt::timestamptz IS NULL OR (k.at, k.id::text) < (@afterAt::timestamptz, @afterId::text))
      AND _readable_at(c.r, k.at, NULL)
    ORDER BY 4 DESC, 2 DESC
    LIMIT @limit
  )
  UNION ALL
  SELECT 'ending', s.program_id::text, s.student_id, s.ending_since, s.program_name
  FROM _summaries s
  WHERE s.ending_since IS NOT NULL
    AND s.program_id IS NOT NULL
    AND (@afterAt::timestamptz IS NULL OR (s.ending_since, s.program_id::text) < (@afterAt::timestamptz, @afterId::text))
)
SELECT i.kind, i.id, i.student_id, i.at, i.title, p.username, p.avatar_url
FROM _items i
JOIN profiles p ON p.id = i.student_id
ORDER BY i.at DESC, i.id DESC
LIMIT @limit
''';
