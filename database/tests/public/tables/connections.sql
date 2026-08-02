BEGIN;

SELECT plan(31);

SELECT has_table('public'::name, 'connections'::name);

SELECT columns_are(
               'public',
               'connections',
               ARRAY [
                   'initiator_id',
                   'target_id',
                   'initiator_role',
                   'target_role',
                   'domain',
                   'status',
                   'created_at',
                   'status_by'
                   ]
       );

SELECT col_type_is('public'::name, 'connections'::name, 'initiator_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'target_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'initiator_role'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'target_role'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'domain'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'status'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'status_by'::name, 'text'::name);

SELECT has_pk('public'::name, 'connections'::name, 'connections has a primary key');
SELECT col_is_pk('public'::name, 'connections'::name, ARRAY ['initiator_id', 'target_id', 'domain'], '(initiator_id, target_id, domain) is the composite primary key');

SELECT col_not_null('public'::name, 'connections'::name, 'initiator_id'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'target_id'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'initiator_role'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'target_role'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'domain'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'status'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'created_at'::name);

SELECT col_default_is('public', 'connections', 'status', 'pending', 'status default is pending');
SELECT col_default_is('public', 'connections', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'connections', 'initiator_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'connections', 'target_id', 'public', 'profiles', 'id');

SELECT fk_ok('public', 'connections', 'status_by', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'connections'::name, 'idx_connections_target_id'::name);
SELECT has_index('public'::name, 'connections'::name, 'connections_status_idx'::name);

-- fixtures for the vocabulary assertions below
DO
$$
BEGIN
    PERFORM create_test_profile('conn-a');
    PERFORM create_test_profile('conn-b');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status_by)
               VALUES ('conn-a', 'conn-b', 'COACH', 'STUDENT', 'fitness', 'conn-a')
               $$,
               'a connection between two people in a known domain with known roles'
       );

SELECT throws_ok(
               $$
               INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain)
               VALUES ('conn-a', 'conn-a', 'PEER', 'PEER', 'running')
               $$,
               '23514',
               NULL,
               'you cannot connect to yourself'
       );

SELECT throws_ok(
               $$
               INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain)
               VALUES ('conn-a', 'conn-b', 'SENSEI', 'PEER', 'running')
               $$,
               '23514',
               NULL,
               'an unknown role is rejected'
       );

-- Domain is deliberately unconstrained — it is a partition label the code never branches on, and
-- ConnectionDomain.fromString is what keeps unknown values out on the way in. Adding an activity
-- should not need a migration.
SELECT lives_ok(
               $$
               INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain)
               VALUES ('conn-a', 'conn-b', 'PEER', 'PEER', 'cycling')
               $$,
               'a new domain needs no schema change'
       );

SELECT throws_ok(
               $$
               INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
               VALUES ('conn-a', 'conn-b', 'PEER', 'PEER', 'running', 'nonsense')
               $$,
               '23514',
               NULL,
               'an unknown status is rejected'
       );

SELECT * FROM finish();

ROLLBACK;
