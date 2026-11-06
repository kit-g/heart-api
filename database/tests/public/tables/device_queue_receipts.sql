BEGIN;

SELECT plan(9);

SELECT has_table('public'::name, 'device_queue_receipts'::name);

SELECT columns_are(
               'public',
               'device_queue_receipts',
               ARRAY [
                   'id',
                   'recipient_device_id',
                   'sender_device_id',
                   'confirmed_at'
                   ]
       );

SELECT col_is_pk('public'::name, 'device_queue_receipts'::name, 'id'::name);

SELECT col_not_null('public'::name, 'device_queue_receipts'::name, 'recipient_device_id'::name);

SELECT col_default_is('public', 'device_queue_receipts', 'confirmed_at', 'now()', 'confirmed when written');

SELECT fk_ok('public', 'device_queue_receipts', 'recipient_device_id', 'public', 'crypto_devices', 'id');
SELECT fk_ok('public', 'device_queue_receipts', 'sender_device_id', 'public', 'crypto_devices', 'id');

SELECT has_index('public'::name, 'device_queue_receipts'::name, 'device_queue_receipts_recipient_idx'::name);
SELECT has_index('public'::name, 'device_queue_receipts'::name, 'device_queue_receipts_confirmed_idx'::name);

SELECT * FROM finish();

ROLLBACK;
