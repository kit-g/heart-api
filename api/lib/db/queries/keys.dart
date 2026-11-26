part of '../db.dart';

/// Taken before publishing, vouching or removing, in a statement of its own, so
/// two at once see each other: two new devices count each other, and a device
/// removed can't remove another in the meantime. A statement reads from the
/// snapshot it started with.
const _lockDevices = '''
SELECT pg_advisory_xact_lock(hashtextextended('crypto_devices:' || @userId, 0))
''';

/// A device id is chosen by the device, so publishing twice answers what is
/// there, and someone else's id answers nothing. A signature only counts if it
/// names a device of the same owner with a place. A device its owner removed stays
/// removed, and says so. A device unseen for a month holds no place. A new one with
/// no place left waits for one: known, so it can remove devices and its day counts,
/// but nothing is sent to it, until it publishes again with room, which gives it a
/// place. Past as many waiting as there are places, it is no device, and `is_full`
/// says why. `added` says this statement added it or gave it a place.
const _publishDevice =
    '''
WITH
_live AS (
  SELECT
    count(*) FILTER (WHERE NOT waiting AND seen_at > now() - INTERVAL '$_unseenDays days') >= $_maxDevices AS is_full,
    count(*) FILTER (WHERE waiting) >= $_maxWaitingDevices AS no_room_to_wait
  FROM crypto_devices
  WHERE user_id = @userId
    AND removed_at IS NULL
),
_inserted AS (
  INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by, waiting)
  SELECT
    @id::uuid,
    @userId,
    @identityKey,
    @signingKey,
    @fallbackKey,
    CASE WHEN voucher.id IS NULL THEN NULL ELSE @signature::text END,
    voucher.id,
    l.is_full
  FROM _live l
  LEFT JOIN crypto_devices voucher
    ON voucher.id = @vouchedBy::uuid
    AND voucher.user_id = @userId
    AND voucher.removed_at IS NULL
    AND NOT voucher.waiting
  WHERE NOT (l.is_full AND l.no_room_to_wait)
  ON CONFLICT (id) DO NOTHING
  RETURNING *
),
_placed AS (
  UPDATE crypto_devices
  SET
    waiting = false,
    seen_at = now()
  WHERE id = @id::uuid
    AND user_id = @userId
    AND removed_at IS NULL
    AND waiting
    AND NOT (SELECT is_full FROM _live)
  RETURNING *
)
SELECT
  id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by, created_at,
  false AS removed, false AS is_full, waiting, true AS added
FROM _inserted
UNION ALL
SELECT
  id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by, created_at,
  false, false, false, true
FROM _placed
UNION ALL
SELECT
  id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by, created_at,
  removed_at IS NOT NULL, false, waiting, false
FROM crypto_devices
WHERE id = @id::uuid
  AND user_id = @userId
  AND NOT EXISTS (SELECT 1 FROM _inserted)
  AND NOT EXISTS (SELECT 1 FROM _placed)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, false, true, false, false
FROM _live
WHERE is_full
  AND no_room_to_wait
  AND NOT EXISTS (SELECT 1 FROM crypto_devices WHERE id = @id::uuid)
''';

/// A device is vouched for once, by another device of the same owner in use, both
/// with a place. The
/// update checks the row it locks, so of two vouches racing, one lands and the
/// other finds it there.
const _vouchForDevice = '''
WITH
_device AS (
  SELECT id, vouched_by, signature
  FROM crypto_devices
  WHERE id = @deviceId::uuid
    AND user_id = @userId
    AND removed_at IS NULL
    AND NOT waiting
),
_voucher AS (
  SELECT id
  FROM crypto_devices
  WHERE id = @vouchedBy::uuid
    AND id <> @deviceId::uuid
    AND user_id = @userId
    AND removed_at IS NULL
    AND NOT waiting
),
_vouched AS (
  UPDATE crypto_devices d
  SET
    vouched_by = v.id,
    signature = @signature
  FROM _voucher v
  WHERE d.id = @deviceId::uuid
    AND d.user_id = @userId
    AND d.removed_at IS NULL
    AND NOT d.waiting
    AND d.vouched_by IS NULL
  RETURNING d.id, d.user_id, d.identity_key, d.signing_key, d.fallback_key, d.signature, d.vouched_by, d.created_at
)
SELECT
  EXISTS (SELECT 1 FROM _device) AS owned,
  EXISTS (SELECT 1 FROM _voucher) AS voucher_owned,
  EXISTS (SELECT 1 FROM _vouched) AS changed,
  coalesce(v.id, d.id) AS id,
  coalesce(v.user_id, d.user_id) AS user_id,
  coalesce(v.identity_key, d.identity_key) AS identity_key,
  coalesce(v.signing_key, d.signing_key) AS signing_key,
  coalesce(v.fallback_key, d.fallback_key) AS fallback_key,
  coalesce(v.signature, d.signature) AS signature,
  coalesce(v.vouched_by, d.vouched_by) AS vouched_by,
  coalesce(v.created_at, d.created_at) AS created_at
FROM (SELECT 1) one
LEFT JOIN _vouched v ON true
LEFT JOIN crypto_devices d ON d.id = (SELECT id FROM _device)
''';

/// The devices in use, and for the owner alone, those waiting for a place, the latest
/// of those removed lately, so a device or a removal they didn't make shows on their
/// other devices, and the day each was last seen. Removing is open to any device of
/// the account's, so the removed ones are capped, or a script adding and removing
/// devices would make the list as long as it liked.
const _listDevices =
    '''
WITH _status AS (
  SELECT NOT _shares_keys_with(@readerId, @ownerId) AS forbidden
)
SELECT
  s.forbidden,
  d.id, d.user_id, d.identity_key, d.signing_key, d.fallback_key, d.signature, d.vouched_by, d.created_at,
  d.removed_at, d.removed_by, d.waiting,
  CASE WHEN @readerId = @ownerId THEN (d.seen_at AT TIME ZONE 'UTC')::date END AS seen_on
FROM _status s
LEFT JOIN LATERAL (
  (
    SELECT *
    FROM crypto_devices
    WHERE user_id = @ownerId
      AND removed_at IS NULL
      AND (NOT waiting OR @readerId = @ownerId)
  )
  UNION ALL
  (
    SELECT *
    FROM crypto_devices
    WHERE user_id = @ownerId
      AND @readerId = @ownerId
      AND removed_at > now() - INTERVAL '$_removedListedDays days'
    ORDER BY removed_at DESC
    LIMIT $_maxRemovedListed
  )
) d ON NOT s.forbidden
ORDER BY d.removed_at DESC NULLS FIRST, d.id
''';

/// The caller's devices that sign what a vouch or a removal says, and whether each
/// is still in use. Their keys never change, so they're read and checked before
/// anything is locked, and the write checks again that they're in use.
const _signers = '''
SELECT id, identity_key, signing_key, removed_at IS NOT NULL AS removed, waiting
FROM crypto_devices
WHERE id = ANY (@ids::uuid[])
  AND user_id = @userId
''';

/// A device removes itself, or one added after it, at once, and one added before it
/// once it has been in use for a day: someone holding only the password adds a
/// device later than the owner's, whose devices remove it before the wait is over,
/// and someone who lost a phone removes it from the new one a day on. `removable_at`
/// says when the wait ends. A removed device gets nothing more, so what waits for it
/// and its keys go now.
const _removeDevice =
    '''
WITH
_target AS (
  SELECT id, created_at
  FROM crypto_devices
  WHERE id = @deviceId::uuid
    AND user_id = @userId
    AND removed_at IS NULL
),
_remover AS (
  SELECT id, created_at
  FROM crypto_devices
  WHERE id = @removedBy::uuid
    AND user_id = @userId
    AND removed_at IS NULL
),
_removable AS (
  SELECT
    CASE
      WHEN t.id = r.id OR (t.created_at, t.id) > (r.created_at, r.id) THEN now()
      ELSE greatest(now(), r.created_at + INTERVAL '$_removalWaitHours hours')
    END AS at
  FROM _target t, _remover r
),
_removed AS (
  UPDATE crypto_devices
  SET
    removed_at = now(),
    removed_by = (SELECT id FROM _remover)
  WHERE id = (SELECT id FROM _target)
    AND (SELECT at FROM _removable) <= now()
  RETURNING id
),
_keys AS (
  DELETE FROM one_time_keys
  WHERE device_id IN (SELECT id FROM _removed)
  RETURNING 1
),
_queue AS (
  DELETE FROM device_queue
  WHERE recipient_device_id IN (SELECT id FROM _removed)
  RETURNING 1
)
SELECT
  EXISTS (SELECT 1 FROM _target) AS found,
  EXISTS (SELECT 1 FROM _remover) AS remover_in_use,
  EXISTS (SELECT 1 FROM _removed) AS removed,
  (SELECT at FROM _removable) AS removable_at
''';

/// A device showing it's in use, at most once an hour, so it keeps its place.
const _seeDevice = '''
UPDATE crypto_devices
SET seen_at = now()
WHERE id = @deviceId::uuid
  AND user_id = @userId
  AND removed_at IS NULL
  AND seen_at < now() - INTERVAL '1 hour'
''';

const _replaceFallbackKey = '''
UPDATE crypto_devices
SET fallback_key = @key
WHERE id = @deviceId::uuid
  AND user_id = @userId
  AND removed_at IS NULL
RETURNING id
''';

/// Taken before counting, in a statement of its own: a statement counts from
/// the snapshot it started with, so a lock inside it would wait for another
/// upload and then count as if that one never happened.
const _lockDevice = '''
SELECT id
FROM crypto_devices
WHERE id = @deviceId::uuid
  AND user_id = @userId
  AND removed_at IS NULL
FOR UPDATE
''';

const _addOneTimeKeys =
    '''
WITH
_device AS (
  SELECT id
  FROM crypto_devices
  WHERE id = @deviceId::uuid
    AND user_id = @userId
    AND removed_at IS NULL
),
_incoming AS (
  SELECT value ->> 'id' AS key_id, value ->> 'key' AS key
  FROM jsonb_array_elements(@keys::jsonb)
),
_existing AS (
  SELECT count(*) AS n FROM one_time_keys WHERE device_id = @deviceId::uuid
),
_new AS (
  SELECT count(*) AS n
  FROM _incoming i
  WHERE NOT EXISTS (
    SELECT 1 FROM one_time_keys k WHERE k.device_id = @deviceId::uuid AND k.key_id = i.key_id
  )
),
_fits AS (
  SELECT (SELECT n FROM _existing) + (SELECT n FROM _new) <= $_maxOneTimeKeys AS fits
),
_inserted AS (
  INSERT INTO one_time_keys (device_id, key_id, key)
  SELECT d.id, i.key_id, i.key
  FROM _device d, _incoming i, _fits f
  WHERE f.fits
  ON CONFLICT (device_id, key_id) DO NOTHING
  RETURNING 1
)
SELECT
  EXISTS (SELECT 1 FROM _device) AS owned,
  (SELECT fits FROM _fits) AS fits,
  (SELECT n FROM _existing) + (SELECT count(*) FROM _inserted) AS count
''';

const _countOneTimeKeys = '''
SELECT
  EXISTS (
    SELECT 1 FROM crypto_devices
    WHERE id = @deviceId::uuid AND user_id = @userId AND removed_at IS NULL
  ) AS owned,
  (SELECT count(*) FROM one_time_keys WHERE device_id = @deviceId::uuid) AS count
''';

/// Picking and deleting in one statement, with the pick locked and skipping what
/// someone else is taking, is what keeps a key from going out twice. A device with
/// none left answers no single-use key, and its fallback key stands in.
const _claimKeys =
    '''
WITH
_status AS (
  SELECT NOT _shares_keys_with(@claimerId, @ownerId) AS forbidden
),
_count AS (
  INSERT INTO key_claims (claimer_id, owner_id)
  SELECT @claimerId, @ownerId
  FROM _status
  WHERE NOT forbidden
  ON CONFLICT (claimer_id, owner_id) DO UPDATE
  SET
    claims = CASE WHEN key_claims.window_start < now() - INTERVAL '1 hour' THEN 1 ELSE key_claims.claims + 1 END,
    window_start = CASE WHEN key_claims.window_start < now() - INTERVAL '1 hour' THEN now() ELSE key_claims.window_start END
  RETURNING claims
),
_devices AS (
  SELECT d.*
  FROM crypto_devices d, _count c
  WHERE d.user_id = @ownerId
    AND d.removed_at IS NULL
    AND NOT d.waiting
    AND (@deviceIds::uuid[] IS NULL OR d.id = ANY (@deviceIds::uuid[]))
    AND c.claims <= $_maxKeyClaims
),
_picked AS (
  SELECT
    d.id AS device_id,
    (
      SELECT k.key_id
      FROM one_time_keys k
      WHERE k.device_id = d.id
      ORDER BY k.key_id
      LIMIT 1
      FOR UPDATE SKIP LOCKED
    ) AS key_id
  FROM _devices d
),
_taken AS (
  DELETE FROM one_time_keys k
  USING _picked p
  WHERE k.device_id = p.device_id
    AND k.key_id = p.key_id
  RETURNING k.device_id, k.key_id, k.key
)
SELECT
  s.forbidden,
  (SELECT claims FROM _count) AS claims,
  d.id, d.user_id, d.identity_key, d.signing_key, d.fallback_key, d.signature, d.vouched_by, d.created_at,
  t.key_id,
  t.key
FROM _status s
LEFT JOIN _devices d ON true
LEFT JOIN _taken t ON t.device_id = d.id
ORDER BY d.id
''';

/// An id names one item from one device to another, whether it still waits or
/// was confirmed, so sending it again delivers nothing new, and an id another
/// pair holds is taken. Who may send is settled before either.
const _enqueue =
    '''
WITH
_seen AS (
  SELECT recipient_device_id, sender_device_id FROM device_queue WHERE id = @id::uuid
  UNION ALL
  SELECT recipient_device_id, sender_device_id FROM device_queue_receipts WHERE id = @id::uuid
),
_sender AS (
  SELECT id
  FROM crypto_devices
  WHERE id = @senderDeviceId::uuid
    AND user_id = @userId
    AND removed_at IS NULL
    AND NOT waiting
),
_recipient AS (
  SELECT id, user_id
  FROM crypto_devices
  WHERE id = @recipientDeviceId::uuid
    AND removed_at IS NULL
    AND NOT waiting
    AND _shares_keys_with(@userId, user_id)
),
_recent AS (
  SELECT EXISTS (
    SELECT 1
    FROM device_queue
    WHERE recipient_device_id = @recipientDeviceId::uuid
      AND created_at > now() - INTERVAL '1 minute'
  ) AS recent
),
_load AS (
  SELECT count(*) >= $_maxQueuedPerPair AS is_full
  FROM device_queue
  WHERE recipient_device_id = @recipientDeviceId::uuid
    AND sender_device_id = @senderDeviceId::uuid
),
_inserted AS (
  INSERT INTO device_queue (id, recipient_device_id, sender_device_id, kind, content)
  SELECT @id::uuid, r.id, s.id, @kind, @content
  FROM _recipient r, _sender s, _load l
  WHERE NOT l.is_full
    AND NOT EXISTS (SELECT 1 FROM _seen)
  ON CONFLICT (id) DO NOTHING
  RETURNING 1
)
SELECT
  EXISTS (SELECT 1 FROM _sender) AS sender_owned,
  NOT EXISTS (SELECT 1 FROM _recipient) AS forbidden,
  EXISTS (
    SELECT 1
    FROM _seen
    WHERE (recipient_device_id, sender_device_id) IS DISTINCT FROM (@recipientDeviceId::uuid, @senderDeviceId::uuid)
  ) AS taken,
  EXISTS (SELECT 1 FROM _seen) AS seen,
  (SELECT is_full FROM _load) AS is_full,
  EXISTS (SELECT 1 FROM _inserted) AS inserted,
  CASE
    WHEN EXISTS (SELECT 1 FROM _inserted) AND NOT (SELECT recent FROM _recent) THEN (SELECT user_id FROM _recipient)
  END AS notify
''';

/// A block stops what was sent before it, too. The sender's account is the one the
/// server knows, not one the item claims.
const _listQueue = '''
SELECT q.id, q.recipient_device_id, q.sender_device_id, s.user_id AS sender_user_id, q.kind, q.content, q.created_at
FROM device_queue q
JOIN crypto_devices d ON d.id = q.recipient_device_id
LEFT JOIN crypto_devices s ON s.id = q.sender_device_id
WHERE q.recipient_device_id = @deviceId::uuid
  AND d.user_id = @userId
  AND NOT coalesce(_blocked_between(d.user_id, s.user_id), false)
ORDER BY q.seq
LIMIT @limit
''';

/// The item goes, and its id stays behind for a sender's retry to find.
const _confirmQueued = '''
WITH
_confirmed AS (
  DELETE FROM device_queue q
  USING crypto_devices d
  WHERE d.id = q.recipient_device_id
    AND d.user_id = @userId
    AND q.recipient_device_id = @deviceId::uuid
    AND q.id = ANY (@ids::uuid[])
  RETURNING q.seq, q.id, q.recipient_device_id, q.sender_device_id
),
_receipts AS (
  INSERT INTO device_queue_receipts (id, recipient_device_id, sender_device_id)
  SELECT id, recipient_device_id, sender_device_id
  FROM _confirmed
  ON CONFLICT (id) DO NOTHING
  RETURNING id
)
SELECT seq FROM _confirmed
''';

/// Whoever `_shares_keys_with` says shares keys, so the people told to look are
/// the people allowed to.
const _listKeyPeers = '''
SELECT DISTINCT p.peer
FROM connections c
CROSS JOIN LATERAL (
  SELECT CASE WHEN c.initiator_id = @userId THEN c.target_id ELSE c.initiator_id END AS peer
) p
WHERE @userId IN (c.initiator_id, c.target_id)
  AND _shares_keys_with(@userId, p.peer)
''';
