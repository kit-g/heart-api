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

const _pushAudience = '''
SELECT
  coalesce(_blocked_between(@userId, @actorId::text), false) AS blocked,
  (
    SELECT delivery FROM push_preferences
    WHERE user_id = @userId AND topic = @topic AND connection_id = @connectionId::uuid
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
  ) AS devices
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
const _claimDueDigests = '''
DELETE FROM push_digests d
WHERE extract(hour FROM now() AT TIME ZONE 'UTC' + make_interval(mins => coalesce(
  (
    SELECT t.utc_offset_minutes
    FROM device_tokens t
    WHERE t.profile_id = d.user_id
    ORDER BY t.last_seen_at DESC
    LIMIT 1
  ),
  0
))) = @localHour
RETURNING d.user_id, d.topic
''';
