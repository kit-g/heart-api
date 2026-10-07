@Tags(['db'])
library;

import 'dart:typed_data';

import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `ApiTokenService` queries against a live
/// Postgres: minting under the active-token cap, listing, revoking, and the
/// one-round-trip authenticate-and-count statement with both rate-limit
/// windows.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<(ApiToken, Uint8List)> mint(String userId, {String name = 'n', DateTime? expiresAt}) async {
    final secret = TokenSecret.mint();
    final hash = TokenSecret.hash(secret);
    final token = await h.db.createToken(
      userId: userId,
      name: name,
      purpose: ApiTokenPurpose.script,
      expiresAt: expiresAt,
      tokenHash: hash,
      hint: TokenSecret.hint(secret),
    );
    return (token!, hash);
  }

  group('createToken', () {
    test('stores the token and returns it without the secret', () async {
      final user = await h.seedProfile();
      final (token, _) = await mint(user, name: 'my sheet');

      expect(token.name, 'my sheet');
      expect(token.purpose, ApiTokenPurpose.script);
      expect(token.scopes, ['read']);
      expect(token.isActive(), isTrue);
    });

    test('refuses a sixth active token, but revoked and expired ones do not count', () async {
      final user = await h.seedProfile();
      final first = (await mint(user)).$1;
      await mint(user, expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)));
      for (var i = 0; i < ApiToken.maxActive - 1; i++) {
        await mint(user);
      }

      final secret = TokenSecret.mint();
      Future<ApiToken?> sixth() => h.db.createToken(
        userId: user,
        name: 'one too many',
        tokenHash: TokenSecret.hash(secret),
        hint: TokenSecret.hint(secret),
      );
      expect(await sixth(), isNull);

      await h.db.revokeToken(userId: user, tokenId: first.id);
      expect(await sixth(), isNotNull);
    });
  });

  group('listTokens and revokeToken', () {
    test('lists newest first, revoked included; only the owner can revoke', () async {
      final owner = await h.seedProfile();
      final other = await h.seedProfile();
      final (older, _) = await mint(owner, name: 'older');
      final (newer, _) = await mint(owner, name: 'newer');

      expect(await h.db.revokeToken(userId: other, tokenId: older.id), isFalse);
      expect(await h.db.revokeToken(userId: owner, tokenId: older.id), isTrue);

      final listed = (await h.db.listTokens(owner)).toList();
      expect(listed.map((t) => t.id), [newer.id, older.id]);
      expect(listed.last.revokedAt, isNotNull);

      final firstRevocation = listed.last.revokedAt;
      expect(await h.db.revokeToken(userId: owner, tokenId: older.id), isTrue);
      final again = (await h.db.listTokens(owner)).last;
      expect(again.revokedAt, firstRevocation);
    });
  });

  group('useToken', () {
    test('authenticates, counts both windows and marks the token used', () async {
      final user = await h.seedProfile();
      final (token, hash) = await mint(user);

      final first = await h.db.useToken(hash);
      expect(first?.userId, user);
      expect(first?.purpose, ApiTokenPurpose.script);
      expect(first?.minuteCount, 1);
      expect(first?.dayCount, 1);

      final second = await h.db.useToken(hash);
      expect(second?.minuteCount, 2);
      expect(second?.dayCount, 2);

      final listed = (await h.db.listTokens(user)).single;
      expect(listed.id, token.id);
      expect(listed.lastUsedAt, isNotNull);
    });

    test('a request that does not count authenticates without moving either window', () async {
      final user = await h.seedProfile();
      final (_, hash) = await mint(user);
      await h.db.useToken(hash);

      final free = await h.db.useToken(hash, count: false);
      expect(free?.userId, user);
      expect(free?.minuteCount, 1);
      expect(free?.dayCount, 1);
    });

    test('tokens of one account share its counters', () async {
      final user = await h.seedProfile();
      final (_, a) = await mint(user);
      final (_, b) = await mint(user);

      await h.db.useToken(a);
      final use = await h.db.useToken(b);
      expect(use?.minuteCount, 2);
    });

    test('a window that has run out restarts; the other keeps counting', () async {
      final user = await h.seedProfile();
      final (_, hash) = await mint(user);
      await h.db.useToken(hash);
      await h.exec(
        "UPDATE api_usage SET minute_start = now() - interval '2 minutes', minute_count = 20 WHERE user_id = @u",
        {'u': user},
      );

      final afterMinute = await h.db.useToken(hash);
      expect(afterMinute?.minuteCount, 1);
      expect(afterMinute?.dayCount, 2);

      await h.exec(
        "UPDATE api_usage SET day_start = now() - interval '25 hours', day_count = 200 WHERE user_id = @u",
        {'u': user},
      );
      final afterDay = await h.db.useToken(hash);
      expect(afterDay?.dayCount, 1);
      expect(afterDay?.minuteCount, 2);
    });

    test('unknown, revoked and expired tokens authenticate nothing and count nothing', () async {
      final user = await h.seedProfile();
      final (revoked, revokedHash) = await mint(user);
      await h.db.revokeToken(userId: user, tokenId: revoked.id);
      final (_, expiredHash) = await mint(user, expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));

      expect(await h.db.useToken(TokenSecret.hash(TokenSecret.mint())), isNull);
      expect(await h.db.useToken(revokedHash), isNull);
      expect(await h.db.useToken(expiredHash), isNull);

      final rows = await h.exec('SELECT count(*) AS n FROM api_usage WHERE user_id = @u', {'u': user});
      expect(rows.first.toColumnMap()['n'], 0);
    });
  });
}

class _Harness extends DatabaseTestBase;
