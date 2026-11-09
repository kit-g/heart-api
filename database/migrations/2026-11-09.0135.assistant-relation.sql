-- What a reader's assistant may see of an owner: the reader's own view of themselves,
-- and a coach's view of a student who shares it with the coach's assistant. A peer's
-- view never reaches an assistant, and a paused relationship shares nothing.

DROP FUNCTION IF EXISTS _relation(TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION _relation(_reader TEXT, _owner TEXT, _assistant BOOLEAN) RETURNS relation
    LANGUAGE sql
    STABLE
AS
$$
SELECT CASE
    WHEN NOT _assistant THEN r
    WHEN (r).scope = 'self' THEN r
    WHEN (r).scope = 'coach' AND 'assistant' = ANY ((r).shares) THEN r
    ELSE ROW (NULL, FALSE, NULL, '{}', NULL)::relation
END
FROM (SELECT _relation(_reader, _owner) AS r) rel
$$;

COMMENT ON FUNCTION _relation(TEXT, TEXT, BOOLEAN) IS
    'What a reader may see of an owner, and with _assistant what the reader''s assistant may: their own, and a student''s who shares it';
