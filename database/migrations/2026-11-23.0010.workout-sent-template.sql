-- A workout keeps the template id it was sent with while no template answers to it:
-- a sample has no row, and one made offline can arrive after its workouts. A deleted
-- template is told apart by what is remembered of it, its id.

-- Every workout read and write waits behind the change to workouts; it gives up rather
-- than queue them behind a long transaction, and is run again. That change comes last,
-- so nothing else is waited for while it holds them.
SET LOCAL lock_timeout = '5s';

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

-- What is already known of the deleted: a copy's history, and what deleted workouts
-- were linked to.
INSERT INTO archive.deleted_templates (user_id, id, deleted_at)
SELECT user_id, id, max(at)
FROM (
    SELECT p.user_id, c.session_id AS id, c.at
    FROM program_changes c
    JOIN programs p ON p.id = c.program_id
    WHERE c.session_id IS NOT NULL
      AND c.after IS NULL
    UNION ALL
    SELECT d.user_id, d.template_id, d.deleted_at
    FROM archive.deleted_workouts d
    JOIN profiles p ON p.id = d.user_id
    WHERE d.template_id IS NOT NULL
) known
WHERE NOT EXISTS (SELECT 1 FROM templates t WHERE t.id = known.id)
GROUP BY user_id, id
ON CONFLICT (user_id, id) DO NOTHING;

-- A workout and its template can be written at once, neither seeing the other. Both
-- take the template's lock first and look after, so the later one finds the earlier.
CREATE OR REPLACE FUNCTION _lock_template(_id UUID) RETURNS VOID
    LANGUAGE sql
AS
$$
SELECT pg_advisory_xact_lock(hashtextextended(_id::text, 474))
$$;

COMMENT ON FUNCTION _lock_template(UUID) IS
    'Held to the end of the transaction by whoever makes or deletes a template, or has a workout wait for one';

CREATE OR REPLACE FUNCTION _template_arrived() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    PERFORM _lock_template(id) FROM (SELECT id FROM _arrived ORDER BY id) ids;

    DELETE FROM archive.deleted_templates d
    USING _arrived a
    WHERE d.user_id = a.user_id
      AND d.id = a.id;

    -- for anyone else the id is now somebody else's template
    UPDATE workouts w
    SET template_id = CASE WHEN w.user_id = a.user_id THEN a.id END,
        sent_template_id = NULL
    FROM _arrived a
    WHERE w.sent_template_id = a.id
      AND w.template_id IS NULL;
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
    PERFORM _lock_template(id) FROM (SELECT id FROM _gone ORDER BY id) ids;

    INSERT INTO archive.deleted_templates (user_id, id)
    SELECT g.user_id, g.id
    FROM _gone g
    JOIN profiles p ON p.id = g.user_id
    ON CONFLICT (user_id, id) DO UPDATE SET deleted_at = now();

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

-- What becomes of an id a workout is sent with: the owner's template if it is here by
-- now, nothing if it was deleted or is somebody else's, and otherwise kept. A workout
-- someone else entered keeps none.
CREATE OR REPLACE FUNCTION _settle_sent_template() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _owner TEXT;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.sent_template_id IS NOT DISTINCT FROM OLD.sent_template_id THEN
            RETURN NEW;
        END IF;
    END IF;
    IF NEW.template_id IS NOT NULL OR NEW.logged_by IS NOT NULL THEN
        NEW.sent_template_id := NULL;
        RETURN NEW;
    END IF;

    PERFORM _lock_template(NEW.sent_template_id);
    SELECT user_id INTO _owner FROM templates WHERE id = NEW.sent_template_id;
    IF _owner = NEW.user_id THEN
        NEW.template_id := NEW.sent_template_id;
        NEW.sent_template_id := NULL;
    ELSIF _owner IS NOT NULL OR EXISTS (
        SELECT 1
        FROM archive.deleted_templates d
        WHERE d.user_id = NEW.user_id
          AND d.id = NEW.sent_template_id
    ) THEN
        NEW.sent_template_id := NULL;
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _settle_sent_template() IS
    'BEFORE INSERT or UPDATE of sent_template_id on workouts: links, drops or keeps the template id a workout was sent with';

-- The archive keeps the template the owner was shown.
CREATE OR REPLACE FUNCTION _archive_workout() RETURNS TRIGGER AS
$$
BEGIN
    INSERT INTO archive.deleted_workouts (
        id,
        user_id,
        name,
        started_at,
        completed_at,
        created_at,
        calories,
        note,
        pauses,
        template_id,
        program_id,
        exercises
    ) VALUES (
        OLD.id,
        OLD.user_id,
        OLD.name,
        OLD.started_at,
        OLD.completed_at,
        OLD.created_at,
        OLD.calories,
        OLD.note,
        OLD.pauses,
        coalesce(OLD.template_id, OLD.sent_template_id),
        OLD.program_id,
        _workout_exercises(OLD.id)
    )
    ON CONFLICT (id) DO UPDATE
        SET user_id      = excluded.user_id,
            name         = excluded.name,
            started_at   = excluded.started_at,
            completed_at = excluded.completed_at,
            created_at   = excluded.created_at,
            calories     = excluded.calories,
            note         = excluded.note,
            pauses       = excluded.pauses,
            template_id  = excluded.template_id,
            program_id   = excluded.program_id,
            exercises    = excluded.exercises,
            deleted_at   = now(),
            deleted_xid  = pg_current_xact_id();
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- No DROP before the ADD: the column holds what users wrote.
ALTER TABLE IF EXISTS workouts
    ADD COLUMN IF NOT EXISTS sent_template_id UUID;

CREATE INDEX IF NOT EXISTS workouts_sent_template_id_idx
    ON workouts (sent_template_id) WHERE sent_template_id IS NOT NULL;

COMMENT ON COLUMN workouts.sent_template_id IS
    'The template it was sent with, while no template answers to that id; not a reference. NULL once one does, or one that did is deleted';
COMMENT ON INDEX workouts_sent_template_id_idx IS 'The workouts waiting for a template that arrives';

DROP TRIGGER IF EXISTS workouts_settle_sent_template ON workouts;
CREATE TRIGGER workouts_settle_sent_template
    BEFORE INSERT OR UPDATE OF sent_template_id
    ON workouts
    FOR EACH ROW
    WHEN (NEW.sent_template_id IS NOT NULL)
EXECUTE FUNCTION _settle_sent_template();

COMMENT ON TRIGGER workouts_settle_sent_template ON workouts IS 'A workout sent with a template that is not the owner''s yet';
