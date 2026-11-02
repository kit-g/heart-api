BEGIN;

SELECT plan(15);

SELECT has_table('public'::name, 'blocks'::name);

SELECT columns_are(
               'public',
               'blocks',
               ARRAY [
                   'id',
                   'blocker_id',
                   'blocked_id',
                   'created_at',
                   'lifted_at'
                   ]
       );

SELECT col_is_pk('public'::name, 'blocks'::name, 'id'::name);

SELECT col_not_null('public'::name, 'blocks'::name, 'blocker_id'::name);
SELECT col_not_null('public'::name, 'blocks'::name, 'blocked_id'::name);
SELECT col_not_null('public'::name, 'blocks'::name, 'created_at'::name);

SELECT fk_ok('public', 'blocks', 'blocker_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'blocks', 'blocked_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'blocks'::name, 'blocks_live_key'::name);
SELECT index_is_unique('public'::name, 'blocks'::name, 'blocks_live_key'::name);
SELECT has_index('public'::name, 'blocks'::name, 'blocks_blocked_idx'::name);

SELECT has_trigger('public'::name, 'blocks'::name, 'blocks_end_connections'::name);

SELECT has_trigger('public'::name, 'blocks'::name, 'blocks_end_connections'::name);

DO
$$
BEGIN
    PERFORM create_test_profile('block-a');
    PERFORM create_test_profile('block-b');
END
$$;

SELECT throws_ok(
               $$
               INSERT INTO blocks (blocker_id, blocked_id) VALUES ('block-a', 'block-a')
               $$,
               '23514',
               NULL,
               'nobody blocks themselves'
       );

INSERT INTO blocks (blocker_id, blocked_id, lifted_at) VALUES ('block-a', 'block-b', now());
INSERT INTO blocks (blocker_id, blocked_id) VALUES ('block-a', 'block-b');

SELECT is(
               (SELECT count(*) FROM blocks WHERE blocker_id = 'block-a'),
               2::bigint,
               'a lifted block stays beside a new one'
       );

SELECT throws_ok(
               $$
               INSERT INTO blocks (blocker_id, blocked_id) VALUES ('block-a', 'block-b')
               $$,
               '23505',
               NULL,
               'one standing block per direction'
       );

SELECT * FROM finish();

ROLLBACK;
