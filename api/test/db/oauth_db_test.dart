@Tags(['db'])
library;

import 'dart:typed_data';

import 'package:heart/models/oauth.dart';
import 'package:heart/models/tokens.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The OAuth authorization server's queries against a live Postgres: clients,
/// the consent round trip, codes, tokens, rotation with reuse detection,
/// revocation and disconnecting.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();
  const resource = 'https://mcp.example';
  final clients = <String>[];

  setUpAll(h.setupDatabase);
  tearDownAll(() async {
    await h.exec('DELETE FROM oauth_clients WHERE client_id = ANY(@ids)', {'ids': clients});
    await h.teardownDatabase();
  });

  Future<OAuthClient> client({String name = 'Claude'}) async {
    final saved = await h.db.saveClient(
      OAuthClient(
        clientId: 'https://client.example/${h.uid('meta')}',
        kind: .cimd,
        name: name,
        redirectUris: const ['https://client.example/callback'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
      const {'client_name': 'Claude'},
    );
    clients.add(saved.clientId);
    return saved;
  }

  TokenPair pair() {
    final access = TokenSecret.mint(prefix: TokenSecret.accessPrefix);
    return (
      accessHash: TokenSecret.hash(access),
      accessHint: TokenSecret.hint(access),
      accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshHash: TokenSecret.hash(TokenSecret.mint(prefix: TokenSecret.refreshPrefix)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 90)),
    );
  }

  /// Runs the consent round trip to a grant with live tokens.
  Future<(String user, OAuthClient client, TokenPair tokens)> connected({List<String> scopes = const ['read']}) async {
    final user = await h.seedProfile();
    final c = await client();
    final id = await h.db.createRequest(
      clientId: c.clientId,
      redirectUri: c.redirectUris.single,
      codeChallenge: 'challenge',
      scopes: scopes,
      resource: resource,
      ttl: const Duration(minutes: 10),
    );
    final code = TokenSecret.hash(TokenSecret.random());
    await h.db.approveRequest(requestId: id, userId: user, codeHash: code, codeTtl: const Duration(minutes: 1));
    final redeemed = (await h.db.redeemCode(code))!;
    final tokens = pair();
    final issued = await h.db.issueTokens(
      userId: redeemed.userId,
      clientId: redeemed.clientId,
      resource: redeemed.resource,
      scopes: redeemed.scopes,
      tokens: tokens,
    );
    expect(issued, isTrue);
    return (user, c, tokens);
  }

  group('clients', () {
    test('a fetched document is cached and replaced; a registration gets an id', () async {
      final saved = await client(name: 'First');
      expect((await h.db.getClient(saved.clientId))?.name, 'First');

      await h.db.saveClient(
        OAuthClient(
          clientId: saved.clientId,
          kind: .cimd,
          name: 'Renamed',
          redirectUris: saved.redirectUris,
        ),
        const {},
      );
      expect((await h.db.getClient(saved.clientId))?.name, 'Renamed');

      final registered = await h.db.registerClient(
        name: 'ChatGPT',
        redirectUris: const ['https://chatgpt.example/cb'],
        auth: .none,
        metadata: const {'client_name': 'ChatGPT'},
      );
      clients.add(registered.clientId);
      expect(registered.clientId, startsWith('dcr_'));
      expect(registered.kind, ClientKind.dcr);
    });
  });

  group('consent', () {
    test('a request is pending until answered, and approving it records a grant once', () async {
      final user = await h.seedProfile();
      final c = await client();
      final id = await h.db.createRequest(
        clientId: c.clientId,
        redirectUri: c.redirectUris.single,
        codeChallenge: 'x',
        scopes: const ['read'],
        resource: resource,
        state: 'abc',
        ttl: const Duration(minutes: 10),
      );

      final pending = await h.db.getPendingRequest(id);
      expect(pending?.clientName, 'Claude');
      expect(pending?.state, 'abc');

      final code = TokenSecret.hash(TokenSecret.random());
      final approved = await h.db.approveRequest(
        requestId: id,
        userId: user,
        codeHash: code,
        codeTtl: const Duration(minutes: 1),
      );
      expect(approved?.redirectUri.toString(), c.redirectUris.single);
      expect(await h.db.getPendingRequest(id), isNull);
      expect(
        await h.db.approveRequest(requestId: id, userId: user, codeHash: code, codeTtl: const Duration(minutes: 1)),
        isNull,
        reason: 'answered once',
      );

      final apps = await h.db.listConnectedApps(user);
      expect(apps.single.name, 'Claude');
      expect(apps.single.resource, resource);
    });

    test('approving the same client again widens the grant instead of adding one', () async {
      final user = await h.seedProfile();
      final c = await client();
      for (final scope in ['read', 'write:templates']) {
        final id = await h.db.createRequest(
          clientId: c.clientId,
          redirectUri: c.redirectUris.single,
          codeChallenge: 'x',
          scopes: [scope],
          resource: resource,
          ttl: const Duration(minutes: 10),
        );
        await h.db.approveRequest(
          requestId: id,
          userId: user,
          codeHash: TokenSecret.hash(TokenSecret.random()),
          codeTtl: const Duration(minutes: 1),
        );
      }
      final apps = await h.db.listConnectedApps(user);
      expect(apps, hasLength(1));
      expect(apps.single.scopes, ['read', 'write:templates']);
    });

    test('a denied request is gone', () async {
      final c = await client();
      final id = await h.db.createRequest(
        clientId: c.clientId,
        redirectUri: c.redirectUris.single,
        codeChallenge: 'x',
        scopes: const ['read'],
        resource: resource,
        state: 's',
        ttl: const Duration(minutes: 10),
      );
      expect((await h.db.denyRequest(id))?.state, 's');
      expect(await h.db.getPendingRequest(id), isNull);
    });

    test('a code is spent once and expires', () async {
      final user = await h.seedProfile();
      final c = await client();
      Future<Uint8List> approvedCode({required Duration ttl}) async {
        final id = await h.db.createRequest(
          clientId: c.clientId,
          redirectUri: c.redirectUris.single,
          codeChallenge: 'x',
          scopes: const ['read'],
          resource: resource,
          ttl: const Duration(minutes: 10),
        );
        final code = TokenSecret.hash(TokenSecret.random());
        await h.db.approveRequest(requestId: id, userId: user, codeHash: code, codeTtl: ttl);
        return code;
      }

      final code = await approvedCode(ttl: const Duration(minutes: 1));
      expect((await h.db.redeemCode(code))?.userId, user);
      expect(await h.db.redeemCode(code), isNull, reason: 'single use');

      final stale = await approvedCode(ttl: Duration.zero);
      expect(await h.db.redeemCode(stale), isNull, reason: 'expired');
    });
  });

  group('tokens', () {
    test('an access token is bound to its resource and client, and stays out of personal tokens', () async {
      final (user, c, tokens) = await connected();

      final use = await h.db.useToken(tokens.accessHash);
      expect(use?.userId, user);
      expect(use?.resource, resource);
      expect(use?.clientId, c.clientId);

      expect(await h.db.listTokens(user), isEmpty);
      final secret = TokenSecret.mint();
      for (var i = 0; i < 5; i++) {
        final minted = await h.db.createToken(
          userId: user,
          name: 'pat $i',
          tokenHash: TokenSecret.hash('$secret$i'),
          hint: 'abcd',
        );
        expect(minted, isNotNull, reason: 'OAuth tokens never count toward the cap');
      }
    });

    test('a refresh token rotates once; presenting it again revokes the grant', () async {
      final (user, c, first) = await connected();

      final second = pair();
      final rotated = await h.db.rotateRefreshToken(
        refreshHash: first.refreshHash,
        clientId: c.clientId,
        tokens: second,
      );
      expect(rotated.outcome, RefreshOutcome.rotated);
      expect(rotated.scopes, ['read']);
      expect(await h.db.useToken(second.accessHash), isNotNull);
      expect(await h.db.useToken(first.accessHash), isNotNull, reason: 'a live access token survives rotation');

      final replay = await h.db.rotateRefreshToken(
        refreshHash: first.refreshHash,
        clientId: c.clientId,
        tokens: pair(),
      );
      expect(replay.outcome, RefreshOutcome.reused);
      expect(await h.db.useToken(second.accessHash), isNull);
      expect(await h.db.listConnectedApps(user), isEmpty);

      final after = await h.db.rotateRefreshToken(
        refreshHash: second.refreshHash,
        clientId: c.clientId,
        tokens: pair(),
      );
      expect(after.outcome, RefreshOutcome.invalid);
    });

    test("another client can't use or revoke a client's refresh token", () async {
      final (_, c, tokens) = await connected();
      final other = await client();

      final stolen = await h.db.rotateRefreshToken(
        refreshHash: tokens.refreshHash,
        clientId: other.clientId,
        tokens: pair(),
      );
      expect(stolen.outcome, RefreshOutcome.invalid);

      await h.db.revokeOAuthToken(tokenHash: tokens.refreshHash, clientId: other.clientId);
      final mine = await h.db.rotateRefreshToken(refreshHash: tokens.refreshHash, clientId: c.clientId, tokens: pair());
      expect(mine.outcome, RefreshOutcome.rotated);
    });

    test('revoking an access token kills it alone; revoking a refresh token takes the grant', () async {
      final (user, c, tokens) = await connected();

      await h.db.revokeOAuthToken(tokenHash: tokens.accessHash, clientId: c.clientId);
      expect(await h.db.useToken(tokens.accessHash), isNull);
      expect(await h.db.listConnectedApps(user), hasLength(1));

      await h.db.revokeOAuthToken(tokenHash: tokens.refreshHash, clientId: c.clientId);
      expect(await h.db.listConnectedApps(user), isEmpty);
    });

    test('disconnecting an app revokes everything under it, for its owner only', () async {
      final (user, _, tokens) = await connected();
      final other = await h.seedProfile();
      final grant = (await h.db.listConnectedApps(user)).single;

      expect(await h.db.disconnectApp(userId: other, grantId: grant.id), isFalse);
      expect(await h.db.disconnectApp(userId: user, grantId: grant.id), isTrue);
      expect(await h.db.useToken(tokens.accessHash), isNull);
      expect(
        await h.db.disconnectApp(userId: user, grantId: grant.id),
        isFalse,
        reason: 'already gone',
      );
    });
  });
}

class _Harness extends DatabaseTestBase;
