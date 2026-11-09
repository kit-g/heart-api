part of '../db.dart';

/// A reaction as it reads back, on one target column, `r` being the row and
/// `author` its author's profile.
String _reactionColumns(CommentTarget target) =>
    '''
r.id,
r.author_id,
author.username AS author_name,
r.kind,
r.created_at,
r.${target.column} AS target_id,
'${target.value}' AS target_type''';

/// The reader's standing towards the target, by the comments' rule: whoever can
/// comment on a thing can react to it. No row when the target doesn't exist.
const _reactionAccess =
    '''
_access AS (
  $_commentTargetAccess
)''';

/// One person's one reaction on [target], left or with its word changed, in the
/// same statement as the check that they may. A changed word keeps when it was
/// first left; `created` is whether this statement made the row, which a fresh
/// insert leaves `xmax` at zero to say. The owner is told once per person per
/// workout: `notify` is them, when this reaction is that once.
///
/// The last row stands alone when the reader may not react: `related` and
/// `readable` say why. No row when the target doesn't exist.
String _setReaction(CommentTarget target) =>
    '''
WITH
$_reactionAccess,
_written AS (
  INSERT INTO reactions (author_id, kind, ${target.column}, created_at)
  SELECT @authorId, @kind, @targetId::uuid, least(coalesce(@at::timestamptz, now()), now())
  FROM _access a
  WHERE a.readable
  ON CONFLICT (${target.column}, author_id) WHERE ${target.column} IS NOT NULL DO UPDATE
  SET kind = EXCLUDED.kind
  RETURNING *, xmax = 0 AS created
),
_noticed AS (
  INSERT INTO reaction_notices (author_id, workout_id)
  SELECT @authorId, ($_commentTargetWorkout)
  FROM _written w, _access a
  WHERE w.created
    AND a.owner_id <> @authorId
  ON CONFLICT DO NOTHING
  RETURNING 1
)
SELECT
  ${_reactionColumns(target)},
  r.created,
  CASE WHEN EXISTS (SELECT 1 FROM _noticed) THEN a.owner_id END AS notify,
  a.related,
  a.readable
FROM _access a
LEFT JOIN _written r ON true
LEFT JOIN profiles author ON author.id = r.author_id
''';

String _removeReaction(CommentTarget target) =>
    '''
DELETE FROM reactions
WHERE author_id = @authorId
  AND ${target.column} = @targetId::uuid
''';

/// A page of who reacted to [target], newest first by when they did, with the
/// counts of every word and the reader's own, in one statement: they agree with
/// each other, and with the check that the reader may see them. Anyone a block
/// stands between the reader and is left out of all three.
///
/// One row, when the target exists: `related` and `readable` say whether the
/// reader may see it, and the rest is empty when they may not.
String _getReactions(CommentTarget target) =>
    '''
WITH
$_reactionAccess,
_visible AS (
  SELECT r.*
  FROM reactions r, _access a
  WHERE a.readable
    AND r.${target.column} = @targetId::uuid
    AND NOT _blocked_between(@readerId, r.author_id)
),
_page AS (
  SELECT ${_reactionColumns(target)}
  FROM _visible r
  LEFT JOIN profiles author ON author.id = r.author_id
  WHERE @cursor::uuid IS NULL
     OR (r.created_at, r.id) < (SELECT c.created_at, c.id FROM reactions c WHERE c.id = @cursor::uuid)
  ORDER BY r.created_at DESC, r.id DESC
  LIMIT @limit
)
SELECT
  a.related,
  a.readable,
  coalesce(
    (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at DESC, p.id DESC) FROM _page p),
    '[]'::jsonb
  ) AS page,
  coalesce(
    (SELECT jsonb_object_agg(k.kind, k.n) FROM (SELECT kind, count(*) AS n FROM _visible GROUP BY kind) k),
    '{}'::jsonb
  ) AS counts,
  (SELECT v.kind FROM _visible v WHERE v.author_id = @readerId) AS mine
FROM _access a
''';

final _setReactionSql = {for (final target in CommentTarget.values) target: _setReaction(target)};

final _removeReactionSql = {for (final target in CommentTarget.values) target: _removeReaction(target)};

final _getReactionsSql = {for (final target in CommentTarget.values) target: _getReactions(target)};
