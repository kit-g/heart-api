BEGIN;

SELECT plan(19);

SELECT has_table('public'::name, 'crypto_devices'::name);
SELECT columns_are(
               'public', 'crypto_devices',
               ARRAY ['id', 'user_id', 'identity_key', 'signing_key', 'fallback_key', 'signature', 'vouched_by', 'created_at', 'removed_at']
       );
SELECT col_is_pk('public'::name, 'crypto_devices'::name, 'id'::name);
SELECT fk_ok('public', 'crypto_devices', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'crypto_devices', 'vouched_by', 'public', 'crypto_devices', 'id');
SELECT has_index('public'::name, 'crypto_devices'::name, 'crypto_devices_user_idx'::name);

SELECT has_table('public'::name, 'one_time_keys'::name);
SELECT columns_are('public', 'one_time_keys', ARRAY ['device_id', 'key_id', 'key']);
SELECT col_is_pk('public'::name, 'one_time_keys'::name, ARRAY ['device_id', 'key_id'], 'one key per device and name');
SELECT fk_ok('public', 'one_time_keys', 'device_id', 'public', 'crypto_devices', 'id');

SELECT has_table('public'::name, 'key_claims'::name);
SELECT col_is_pk('public'::name, 'key_claims'::name, ARRAY ['claimer_id', 'owner_id'], 'one count per pair');

SELECT has_table('public'::name, 'device_queue'::name);
SELECT columns_are(
               'public', 'device_queue',
               ARRAY ['seq', 'id', 'recipient_device_id', 'sender_device_id', 'kind', 'content', 'created_at']
       );
SELECT col_is_pk('public'::name, 'device_queue'::name, 'seq'::name);
SELECT col_is_unique('public', 'device_queue', ARRAY ['id'], 'an item arrives once');
SELECT fk_ok('public', 'device_queue', 'recipient_device_id', 'public', 'crypto_devices', 'id');
SELECT fk_ok('public', 'device_queue', 'sender_device_id', 'public', 'crypto_devices', 'id');
SELECT has_index('public'::name, 'device_queue'::name, 'device_queue_recipient_idx'::name);

SELECT * FROM finish();

ROLLBACK;
