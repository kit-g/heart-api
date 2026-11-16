part of '../db.dart';

const _listPushPreferences = '''
SELECT topic, connection_id, delivery
FROM push_preferences
WHERE user_id = @userId
ORDER BY topic, connection_id NULLS FIRST
''';

const _setPushPreferenceForTopic = '''
INSERT INTO push_preferences (user_id, topic, delivery)
VALUES (@userId, @topic, @delivery)
ON CONFLICT (user_id, topic) WHERE connection_id IS NULL DO UPDATE
SET delivery = EXCLUDED.delivery, updated_at = now()
RETURNING id
''';

/// Only about a relationship the person is in.
const _setPushPreferenceForPerson = '''
INSERT INTO push_preferences (user_id, topic, connection_id, delivery)
SELECT @userId, @topic, c.id, @delivery
FROM connections c
WHERE c.id = @connectionId::uuid
  AND @userId IN (c.initiator_id, c.target_id)
ON CONFLICT (user_id, topic, connection_id) WHERE connection_id IS NOT NULL DO UPDATE
SET delivery = EXCLUDED.delivery, updated_at = now()
RETURNING id
''';

const _clearPushPreference = '''
DELETE FROM push_preferences
WHERE user_id = @userId
  AND topic = @topic
  AND connection_id IS NOT DISTINCT FROM @connectionId::uuid
RETURNING id
''';

/// A push that names no relationship is still about a person, so what was said
/// about any relationship with the actor answers for them, the latest said first.
const _pushAudience = '''
SELECT
  coalesce(_blocked_between(@userId, @actorId::text), false) AS blocked,
  (
    SELECT p.delivery
    FROM push_preferences p
    JOIN connections c ON c.id = p.connection_id
    WHERE p.user_id = @userId
      AND p.topic = @topic
      AND (
        c.id = @connectionId::uuid
        OR (
          @connectionId::uuid IS NULL
          AND (c.initiator_id, c.target_id) IN ((@userId, @actorId::text), (@actorId::text, @userId))
        )
      )
    ORDER BY p.updated_at DESC
    LIMIT 1
  ) AS for_person,
  (
    SELECT delivery FROM push_preferences
    WHERE user_id = @userId AND topic = @topic AND connection_id IS NULL
  ) AS for_topic,
  coalesce(
    (
      SELECT jsonb_agg(jsonb_build_object('token', token, 'locale', locale))
      FROM device_tokens
      WHERE profile_id = @userId
    ),
    '[]'::jsonb
  ) AS devices,
  (SELECT nullif(trim(username), '') FROM profiles WHERE id = @actorId::text) AS actor_name
''';

const _queueDigest = '''
INSERT INTO push_digests (user_id, topic)
VALUES (@userId, @topic)
ON CONFLICT (user_id, topic) DO NOTHING
RETURNING user_id
''';

/// Removing what's owed in the same statement that reads it means a person gets
/// one, however many of these overlap, and a failed send waits for no retry. It
/// reaches them tomorrow if something else happens.
///
/// A person's evening runs from [localHour] to midnight, so an hour the schedule
/// missed is caught up later that evening, and what was queued once it began
/// waits for the next one. The device they last used that said its offset
/// decides; one that never said knows nothing of their zone.
const _claimDueDigests = '''
WITH
_owed AS (
  SELECT
    d.user_id,
    d.topic,
    make_interval(mins => coalesce(
      (
        SELECT t.utc_offset_minutes
        FROM device_tokens t
        WHERE t.profile_id = d.user_id
          AND t.utc_offset_minutes IS NOT NULL
        ORDER BY t.last_seen_at DESC
        LIMIT 1
      ),
      0
    )) AS utc_offset
  FROM push_digests d
),
_evening AS (
  SELECT
    user_id,
    topic,
    utc_offset,
    date_trunc('day', now() AT TIME ZONE 'UTC' + utc_offset) + make_interval(hours => @localHour::int) AS starts
  FROM _owed
)
DELETE FROM push_digests d
USING _evening e
WHERE d.user_id = e.user_id
  AND d.topic = e.topic
  AND now() AT TIME ZONE 'UTC' + e.utc_offset >= e.starts
  AND d.created_at AT TIME ZONE 'UTC' + e.utc_offset < e.starts
RETURNING d.user_id, d.topic
''';
