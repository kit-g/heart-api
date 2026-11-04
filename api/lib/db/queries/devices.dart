part of '../db.dart';

const _upsertDevice = '''
INSERT INTO device_tokens (profile_id, platform, token, locale, settings, utc_offset_minutes, last_seen_at)
VALUES (@profileId, @platform, @token, @locale, @settings::jsonb, @utcOffsetMinutes::smallint, now())
ON CONFLICT (token)
DO UPDATE SET
  profile_id         = EXCLUDED.profile_id,
  platform           = EXCLUDED.platform,
  locale             = EXCLUDED.locale,
  settings           = EXCLUDED.settings,
  utc_offset_minutes = coalesce(EXCLUDED.utc_offset_minutes, device_tokens.utc_offset_minutes),
  last_seen_at       = now()
''';

const _listDeviceTokensWithLocale = '''
SELECT token, locale FROM device_tokens WHERE profile_id = @profileId
''';

const _deleteDeviceToken = '''
DELETE FROM device_tokens WHERE token = @token
''';
