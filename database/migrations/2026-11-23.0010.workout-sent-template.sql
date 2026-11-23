-- A workout keeps the template id it was sent with while no template answers to it:
-- a sample has no row, and one made offline can arrive after its workouts. A deleted
-- template is told apart by what is remembered of it, its id.

-- Every workout read and write waits behind this; it gives up rather than queue them
-- behind a long transaction, and is run again.
SET LOCAL lock_timeout = '5s';

-- No DROP before the ADD: the column holds what users wrote.
ALTER TABLE IF EXISTS workouts
    ADD COLUMN IF NOT EXISTS sent_template_id UUID;

CREATE INDEX IF NOT EXISTS workouts_sent_template_id_idx
    ON workouts (sent_template_id) WHERE sent_template_id IS NOT NULL;

COMMENT ON COLUMN workouts.sent_template_id IS
    'The template it was sent with, while no template answers to that id; not a reference. NULL once one does, or one that did is deleted';
COMMENT ON INDEX workouts_sent_template_id_idx IS 'The workouts waiting for a template that arrives';

CREATE TABLE IF NOT EXISTS archive.deleted_templates
(
    user_id    TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    id         UUID        NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id)
);

COMMENT ON TABLE archive.deleted_templates IS 'The ids of templates that have been deleted, and nothing else of them';
COMMENT ON COLUMN archive.deleted_templates.user_id IS 'Whose it was';
COMMENT ON COLUMN archive.deleted_templates.id IS 'The template; one put back under its id is no longer here';
COMMENT ON COLUMN archive.deleted_templates.deleted_at IS 'When; a re-delete moves it';

CREATE OR REPLACE FUNCTION _template_arrived() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    DELETE FROM archive.deleted_templates d
    USING _arrived a
    WHERE d.user_id = a.user_id
      AND d.id = a.id;

    UPDATE workouts w
    SET template_id = a.id,
        sent_template_id = NULL
    FROM _arrived a
    WHERE w.sent_template_id = a.id
      AND w.user_id = a.user_id;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _template_arrived() IS
    'AFTER INSERT on templates: links the workouts sent with a template before it arrived, and forgets it was ever deleted';

DROP TRIGGER IF EXISTS templates_arrived ON templates;
CREATE TRIGGER templates_arrived
    AFTER INSERT
    ON templates
    REFERENCING NEW TABLE AS _arrived
    FOR EACH STATEMENT
EXECUTE FUNCTION _template_arrived();

COMMENT ON TRIGGER templates_arrived ON templates IS 'Templates made, put back, or sent late';

-- An account's own deletion takes its templates with it, and by then there is nobody
-- to remember them for.
CREATE OR REPLACE FUNCTION _template_deleted() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO archive.deleted_templates (user_id, id)
    SELECT g.user_id, g.id
    FROM _gone g
    JOIN profiles p ON p.id = g.user_id
    ON CONFLICT (user_id, id) DO UPDATE SET deleted_at = now();

    -- one that arrived while its workout was being written left it unlinked
    UPDATE workouts w
    SET sent_template_id = NULL
    FROM _gone g
    WHERE w.sent_template_id = g.id
      AND w.user_id = g.user_id;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _template_deleted() IS
    'AFTER DELETE on templates: remembers the ids of those deleted, and has no workout name them';

DROP TRIGGER IF EXISTS templates_deleted ON templates;
CREATE TRIGGER templates_deleted
    AFTER DELETE
    ON templates
    REFERENCING OLD TABLE AS _gone
    FOR EACH STATEMENT
EXECUTE FUNCTION _template_deleted();

COMMENT ON TRIGGER templates_deleted ON templates IS 'Templates deleted, by themselves or with their program';
