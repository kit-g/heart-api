-- What a device confirmed it received. The item itself goes on confirming, and
-- its id stays here, so the same item sent again isn't delivered twice.

DROP TABLE IF EXISTS device_queue_receipts;

CREATE TABLE IF NOT EXISTS device_queue_receipts
(
    id                  UUID PRIMARY KEY,
    recipient_device_id UUID        NOT NULL REFERENCES crypto_devices (id) ON DELETE CASCADE,
    sender_device_id    UUID REFERENCES crypto_devices (id) ON DELETE SET NULL,
    confirmed_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_queue_receipts_recipient_idx ON device_queue_receipts (recipient_device_id);
CREATE INDEX IF NOT EXISTS device_queue_receipts_sender_idx
    ON device_queue_receipts (sender_device_id) WHERE sender_device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS device_queue_receipts_confirmed_idx ON device_queue_receipts (confirmed_at);

COMMENT ON TABLE device_queue_receipts IS 'The id of an item a device confirmed, without its content; kept 90 days';
COMMENT ON COLUMN device_queue_receipts.id IS 'The item''s id, chosen by the sending device';
COMMENT ON COLUMN device_queue_receipts.recipient_device_id IS 'The device that received it';
COMMENT ON COLUMN device_queue_receipts.sender_device_id IS 'The device that sent it; NULL once that device is deleted';
COMMENT ON COLUMN device_queue_receipts.confirmed_at IS 'When the recipient confirmed it';
COMMENT ON INDEX device_queue_receipts_recipient_idx IS 'The cascade when a receiving device is deleted';
COMMENT ON INDEX device_queue_receipts_sender_idx IS 'The SET NULL when a sending device is deleted';
COMMENT ON INDEX device_queue_receipts_confirmed_idx IS 'The daily cleanup';

CREATE OR REPLACE FUNCTION _clean_up_device_queue() RETURNS VOID
    LANGUAGE sql
AS
$$
DELETE FROM device_queue
WHERE created_at < now() - INTERVAL '90 days';

DELETE FROM device_queue_receipts
WHERE confirmed_at < now() - INTERVAL '90 days';
$$;

COMMENT ON FUNCTION _clean_up_device_queue() IS
    'Removes items left unconfirmed for 90 days, and receipts for items confirmed 90 days ago';
