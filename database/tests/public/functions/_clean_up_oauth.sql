BEGIN;

CREATE OR REPLACE FUNCTION test__clean_up_oauth_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_clean_up_oauth'::name);
    RETURN NEXT function_lang_is('public'::name, '_clean_up_oauth'::name, 'sql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__clean_up_oauth_takes_only_what_expired() RETURNS SETOF TEXT AS
$$
DECLARE
    _client TEXT := 'https://cleanup.example/' || uuidv7();
    _stale  UUID;
    _open   UUID;
BEGIN
    RETURN NEXT is((SELECT count(*) FROM oauth_requests WHERE client_id = _client), 0::bigint, 'no requests yet');

    INSERT INTO oauth_clients (client_id, kind, redirect_uris, expires_at)
    VALUES (_client, 'cimd', ARRAY ['https://cleanup.example/cb'], now() + interval '1 hour');
    INSERT INTO oauth_requests (client_id, redirect_uri, code_challenge, scopes, resource, expires_at)
    VALUES (_client, 'https://cleanup.example/cb', 'c', ARRAY ['read'], 'https://mcp.example', now() - interval '2 days')
    RETURNING id INTO _stale;
    INSERT INTO oauth_requests (client_id, redirect_uri, code_challenge, scopes, resource, expires_at)
    VALUES (_client, 'https://cleanup.example/cb', 'c', ARRAY ['read'], 'https://mcp.example', now() + interval '10 minutes')
    RETURNING id INTO _open;

    RETURN NEXT ok((SELECT requests FROM _clean_up_oauth()) >= 1, 'it reports what it deleted');
    RETURN NEXT is((SELECT count(*) FROM oauth_requests WHERE id = _stale), 0::bigint, 'an expired request goes');
    RETURN NEXT is((SELECT count(*) FROM oauth_requests WHERE id = _open), 1::bigint, 'an open one stays');
    RETURN NEXT is((SELECT count(*) FROM oauth_clients WHERE client_id = _client), 1::bigint,
                   'and so does its client, mid-flow');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
