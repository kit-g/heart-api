BEGIN;

SELECT plan(11);

SELECT has_table('public'::name, 'connection_events'::name);
SELECT columns_are('public', 'connection_events', ARRAY ['id', 'connection_id', 'status', 'actor_id', 'at']);
SELECT col_is_pk('public'::name, 'connection_events'::name, 'id'::name);
SELECT col_not_null('public'::name, 'connection_events'::name, 'connection_id'::name);
SELECT col_not_null('public'::name, 'connection_events'::name, 'status'::name);
SELECT col_not_null('public'::name, 'connection_events'::name, 'at'::name);
SELECT col_default_is('public', 'connection_events', 'id', 'uuidv7()', 'id defaults to a v7');
SELECT fk_ok('public', 'connection_events', 'connection_id', 'public', 'connections', 'id');
SELECT fk_ok('public', 'connection_events', 'actor_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'connection_events'::name, 'connection_events_connection_idx'::name);
SELECT has_index('public'::name, 'connection_events'::name, 'connection_events_actor_idx'::name);

SELECT * FROM finish();

ROLLBACK;
