BEGIN;

SELECT plan(13);

SELECT has_table('public'::name, 'api_usage'::name);

SELECT columns_are(
               'public',
               'api_usage',
               ARRAY [
                   'user_id',
                   'minute_start',
                   'minute_count',
                   'day_start',
                   'day_count'
                   ]
       );

SELECT col_type_is('public'::name, 'api_usage'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'api_usage'::name, 'minute_start'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'api_usage'::name, 'minute_count'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'api_usage'::name, 'day_start'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'api_usage'::name, 'day_count'::name, 'integer'::name);

SELECT col_is_pk('public'::name, 'api_usage'::name, 'user_id'::name);

SELECT col_not_null('public'::name, 'api_usage'::name, 'minute_count'::name);
SELECT col_not_null('public'::name, 'api_usage'::name, 'day_count'::name);

SELECT col_default_is('public', 'api_usage', 'minute_count', 0, 'minute_count starts at 0');
SELECT col_default_is('public', 'api_usage', 'day_count', 0, 'day_count starts at 0');

SELECT fk_ok('public', 'api_usage', 'user_id', 'public', 'profiles', 'id');

SELECT * FROM finish();

ROLLBACK;
