-- Skips: a day the user chose not to train, "Not today" (heart-api#202). One
-- tap records the moment, an optional reason, the weather, and the session it
-- set aside. The health snapshot the app records beside it stays on the device,
-- so nothing here can hold one.

DROP TABLE IF EXISTS skips;

CREATE TABLE IF NOT EXISTS skips
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    at          TIMESTAMPTZ NOT NULL,
    reason      TEXT,
    weather     JSONB,
    template_id UUID REFERENCES templates (id) ON DELETE SET NULL,
    program_id  UUID REFERENCES programs (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT skips_reason_check CHECK (reason IS NULL OR reason ~ '^[a-z][a-z0-9_]{0,31}$'),
    CONSTRAINT skips_weather_check CHECK (weather IS NULL OR jsonb_typeof(weather) = 'object')
);

CREATE INDEX IF NOT EXISTS skips_user_id_idx ON skips (user_id, id);
CREATE INDEX IF NOT EXISTS skips_template_id_idx ON skips (template_id) WHERE template_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS skips_program_id_idx ON skips (program_id) WHERE program_id IS NOT NULL;

COMMENT ON TABLE skips IS
    'Days the user chose not to train: the moment, a reason, the weather, the session set aside. Never a health value';
COMMENT ON COLUMN skips.at IS 'When the user decided, by the device''s clock';
COMMENT ON COLUMN skips.reason IS
    'A one-tap tag such as tired, sore, sick, busy or just_no; the tags are the app''s, so only the spelling is checked';
COMMENT ON COLUMN skips.weather IS
    'The conditions at that moment in metric units (temperature, humidity, pressure, pressureTrend); never a location';
COMMENT ON COLUMN skips.template_id IS 'The session set aside, when one was due; NULL once that template is deleted';
COMMENT ON COLUMN skips.program_id IS
    'The program the session belongs to; outlives the session template, NULL once the program is deleted';
COMMENT ON CONSTRAINT skips_reason_check ON skips IS 'A snake_case tag of at most 32 characters';
COMMENT ON INDEX skips_user_id_idx IS 'The owner''s skips, newest first by id';
COMMENT ON INDEX skips_template_id_idx IS 'The SET NULL when a template is deleted';
COMMENT ON INDEX skips_program_id_idx IS 'A program''s skips, which its position is computed from';
