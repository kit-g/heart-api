BEGIN;

SELECT plan(21);

SELECT has_table('public'::name, 'invitations'::name);
SELECT columns_are(
               'public', 'invitations',
               ARRAY ['id', 'inviter_id', 'role', 'domain', 'token_hash', 'name', 'max_uses', 'expires_at', 'canceled_at', 'created_at']
       );
SELECT col_is_pk('public'::name, 'invitations'::name, 'id'::name);
SELECT col_type_is('public'::name, 'invitations'::name, 'token_hash'::name, 'bytea'::name);
SELECT col_is_unique('public', 'invitations', ARRAY ['token_hash'], 'a token hash is unique');
SELECT col_not_null('public'::name, 'invitations'::name, 'inviter_id'::name);
SELECT col_not_null('public'::name, 'invitations'::name, 'expires_at'::name);
SELECT col_default_is('public', 'invitations', 'role', 'COACH', 'an inviter coaches by default');
SELECT col_default_is('public', 'invitations', 'domain', 'fitness', 'in fitness by default');
SELECT col_default_is('public', 'invitations', 'max_uses', '1', 'for one person by default');
SELECT fk_ok('public', 'invitations', 'inviter_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'invitations'::name, 'invitations_inviter_idx'::name);

SELECT has_table('public'::name, 'invitation_responses'::name);
SELECT columns_are('public', 'invitation_responses', ARRAY ['id', 'invitation_id', 'user_id', 'response', 'at']);
SELECT fk_ok('public', 'invitation_responses', 'invitation_id', 'public', 'invitations', 'id');
SELECT fk_ok('public', 'invitation_responses', 'user_id', 'public', 'profiles', 'id');
SELECT has_index('public'::name, 'invitation_responses'::name, 'invitation_responses_user_key'::name);
SELECT index_is_unique('public'::name, 'invitation_responses'::name, 'invitation_responses_user_key'::name);

DO
$$
BEGIN
    PERFORM create_test_profile('invite-a');
END
$$;

SELECT throws_ok(
               $$
               INSERT INTO invitations (inviter_id, role, token_hash, name, expires_at)
               VALUES ('invite-a', 'STUDENT', '\x01', 'Alex', now())
               $$,
               '23514',
               NULL,
               'a student is who accepts, never who invites'
       );
SELECT throws_ok(
               $$ INSERT INTO invitations (inviter_id, token_hash, name, expires_at) VALUES ('invite-a', '\x02', ' ', now()) $$,
               '23514',
               NULL,
               'the person has a name'
       );
SELECT lives_ok(
               $$ INSERT INTO invitations (inviter_id, token_hash, name, expires_at) VALUES ('invite-a', '\x03', 'Alex', now()) $$,
               'a link for a named person'
       );

SELECT * FROM finish();

ROLLBACK;
