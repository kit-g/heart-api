BEGIN;

SELECT plan(25);

SELECT has_table('public'::name, 'api_tokens'::name);

SELECT columns_are(
               'public',
               'api_tokens',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'purpose',
                   'token_hash',
                   'hint',
                   'scopes',
                   'created_at',
                   'last_used_at',
                   'expires_at',
                   'revoked_at'
                   ]
       );

SELECT col_type_is('public'::name, 'api_tokens'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'purpose'::name, 'text'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'token_hash'::name, 'bytea'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'hint'::name, 'text'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'scopes'::name, 'text[]'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'last_used_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'expires_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'api_tokens'::name, 'revoked_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'api_tokens'::name, 'id'::name);
SELECT col_is_unique('public'::name, 'api_tokens'::name, 'token_hash'::name);

SELECT col_not_null('public'::name, 'api_tokens'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'api_tokens'::name, 'name'::name);
SELECT col_not_null('public'::name, 'api_tokens'::name, 'token_hash'::name);
SELECT col_not_null('public'::name, 'api_tokens'::name, 'hint'::name);
SELECT col_not_null('public'::name, 'api_tokens'::name, 'scopes'::name);

SELECT col_default_is('public', 'api_tokens', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'api_tokens', 'scopes', '{read}'::text[], 'scopes default to read');
SELECT col_default_is('public', 'api_tokens', 'created_at', 'now()', 'created_at defaults to now()');

SELECT fk_ok('public', 'api_tokens', 'user_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'api_tokens'::name, 'api_tokens_user_id_idx'::name, ARRAY ['user_id']::name[]);

SELECT * FROM finish();

ROLLBACK;
