BEGIN;

SELECT plan(22);

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
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'connections'::name, 'initiator_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'target_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'initiator_role'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'target_role'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'domain'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'status'::name, 'text'::name);
SELECT col_type_is('public'::name, 'connections'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'connections'::name, 'connections has a primary key');
SELECT col_is_pk('public'::name, 'connections'::name, ARRAY ['initiator_id', 'target_id', 'domain'], '(initiator_id, target_id, domain) is the composite primary key');

SELECT col_not_null('public'::name, 'connections'::name, 'initiator_id'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'target_id'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'initiator_role'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'target_role'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'domain'::name);
SELECT col_not_null('public'::name, 'connections'::name, 'status'::name);

SELECT col_default_is('public', 'connections', 'status', 'pending', 'status default is pending');
SELECT col_default_is('public', 'connections', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'connections', 'initiator_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'connections', 'target_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'connections'::name, 'idx_connections_target_id'::name);

SELECT * FROM finish();

ROLLBACK;
