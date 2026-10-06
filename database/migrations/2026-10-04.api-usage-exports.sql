-- Exports of a whole account are their own allowance on the token surface
-- (heart-api#113): generating one costs far more than a page of reads, so it
-- is counted apart from the request windows.

ALTER TABLE IF EXISTS api_usage
    DROP COLUMN IF EXISTS last_export_at,
    ADD COLUMN IF NOT EXISTS last_export_at TIMESTAMPTZ;

COMMENT ON COLUMN api_usage.last_export_at IS
    'When the account last started a full export; NULL if it never has';
