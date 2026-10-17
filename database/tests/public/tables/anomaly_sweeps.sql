BEGIN;

SELECT plan(7);

SELECT has_table('public'::name, 'anomaly_sweeps'::name);
SELECT columns_are('public', 'anomaly_sweeps', ARRAY ['id', 'swept_at']);
SELECT col_type_is('public'::name, 'anomaly_sweeps'::name, 'id'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'anomaly_sweeps'::name, 'swept_at'::name, 'timestamp with time zone'::name);
SELECT col_is_pk('public'::name, 'anomaly_sweeps'::name, 'id'::name);
SELECT col_not_null('public'::name, 'anomaly_sweeps'::name, 'swept_at'::name);

SELECT throws_ok(
               $$INSERT INTO anomaly_sweeps (id, swept_at) VALUES (false, now())$$,
               '23514',
               NULL,
               'one row only'
       );

SELECT * FROM finish();

ROLLBACK;
