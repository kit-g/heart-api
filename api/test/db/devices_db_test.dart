@Tags(['db'])
library;

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `DeviceService` query strings against a live
/// Postgres: registering a device (upsert-on-token), listing a profile's tokens
/// with their locales, and deleting a token.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String otherId;

  /// Number of rows currently stored for [token].
  Future<int> rowCount(String token) async {
    final rows = await h.exec('SELECT count(*) AS n FROM device_tokens WHERE token = @t', {'t': token});
    return rows.first.toColumnMap()['n'] as int;
  }

  /// The stored (platform, locale, settings) for [token], or null if absent.
  Future<Map<String, dynamic>?> rowFor(String token) async {
    final rows = await h.exec(
      'SELECT platform, locale, settings FROM device_tokens WHERE token = @t',
      {'t': token},
    );
    return rows.isEmpty ? null : rows.first.toColumnMap();
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    otherId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('registerDevice', () {
    test('inserts a new device token with platform, locale, and settings', () async {
      final token = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: ownerId,
        platform: DevicePlatform.ios,
        token: token,
        locale: 'en_CA',
        settings: {'authorized': true, 'alert': 'enabled'},
      );

      final row = await rowFor(token);
      expect(row, isNotNull);
      expect(row!['platform'], 'ios');
      expect(row['locale'], 'en_CA');
      expect(row['settings'], {'authorized': true, 'alert': 'enabled'});
    });

    test('re-registering the same token upserts locale/platform/settings without duplicating', () async {
      final token = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: ownerId,
        platform: DevicePlatform.android,
        token: token,
        locale: 'en',
        settings: {'badge': 'enabled'},
      );
      expect(await rowCount(token), 1);

      // Same token, new attributes — ON CONFLICT (token) updates in place.
      await h.db.registerDevice(
        profileId: ownerId,
        platform: DevicePlatform.web,
        token: token,
        locale: 'ru',
        settings: {'badge': 'disabled', 'sound': 'enabled'},
      );

      expect(await rowCount(token), 1); // still one row, not duplicated
      final row = await rowFor(token);
      expect(row!['platform'], 'web');
      expect(row['locale'], 'ru');
      expect(row['settings'], {'badge': 'disabled', 'sound': 'enabled'});
    });

    test('re-registering an existing token reassigns it to the new profile', () async {
      final token = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: ownerId,
        platform: DevicePlatform.ios,
        token: token,
        locale: 'en',
        settings: const {},
      );

      // The conflict clause sets profile_id = EXCLUDED.profile_id, so the token
      // migrates to whoever last registered it.
      await h.db.registerDevice(
        profileId: otherId,
        platform: DevicePlatform.ios,
        token: token,
        locale: 'en',
        settings: const {},
      );

      expect(await rowCount(token), 1);
      final ownerTokens = await h.db.tokensWithLocale(ownerId);
      final otherTokens = await h.db.tokensWithLocale(otherId);
      expect(ownerTokens.map((t) => t.token), isNot(contains(token)));
      expect(otherTokens.map((t) => t.token), contains(token));
    });
  });

  group('tokensWithLocale', () {
    test('returns every token for the profile paired with its locale', () async {
      // Isolated owner so counts are exact and unaffected by sibling cases.
      final profileId = await h.seedProfile();
      final t1 = h.token + h.uid('tok');
      final t2 = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: profileId,
        platform: DevicePlatform.ios,
        token: t1,
        locale: 'en_CA',
        settings: const {},
      );
      await h.db.registerDevice(
        profileId: profileId,
        platform: DevicePlatform.android,
        token: t2,
        locale: 'ru',
        settings: const {},
      );

      final result = await h.db.tokensWithLocale(profileId);
      expect(result, hasLength(2));
      expect(
        {for (final t in result) t.token: t.locale},
        {t1: 'en_CA', t2: 'ru'},
      );
    });

    test('does not return another profile\'s tokens', () async {
      final mine = await h.seedProfile();
      final theirs = await h.seedProfile();
      final theirToken = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: theirs,
        platform: DevicePlatform.ios,
        token: theirToken,
        locale: 'en',
        settings: const {},
      );

      final result = await h.db.tokensWithLocale(mine);
      expect(result, isEmpty);
    });

    test('returns an empty iterable for a profile with no devices', () async {
      final profileId = await h.seedProfile();
      expect(await h.db.tokensWithLocale(profileId), isEmpty);
    });
  });

  group('deleteToken', () {
    test('removes the matching token', () async {
      final token = h.token + h.uid('tok');
      await h.db.registerDevice(
        profileId: ownerId,
        platform: DevicePlatform.ios,
        token: token,
        locale: 'en',
        settings: const {},
      );
      expect(await rowCount(token), 1);

      await h.db.deleteToken(token);
      expect(await rowCount(token), 0);
    });

    test('deleting an unknown token is a no-op', () async {
      final token = h.token + h.uid('tok');
      // Must not throw even though no row matches.
      await h.db.deleteToken(token);
      expect(await rowCount(token), 0);
    });
  });
}

class _Harness extends DatabaseTestBase;
