import 'package:heart/globals/config.dart';
import 'package:test/test.dart';

/// A misparse here is silent: the deletion path finds no client configured,
/// logs, and deletes the account anyway — leaving the app listed under the
/// user's Apple ID with nothing to show for it.
void main() {
  group('AppleConfig.fromEnv', () {
    const complete = {
      'APPLE_TEAM_ID': 'TEAM123456',
      'APPLE_KEY_ID': 'KEY1234567',
      'APPLE_PRIVATE_KEY': '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
      'APPLE_CLIENT_IDS': 'me.heart-of.ios',
    };

    test('reads a complete environment', () {
      final apple = AppleConfig.fromEnv(complete);

      expect(apple?.teamId, 'TEAM123456');
      expect(apple?.keyId, 'KEY1234567');
      expect(apple?.clients, {'me.heart-of.ios': null});
    });

    test('a client id may carry the redirect its exchange needs', () {
      final apple = AppleConfig.fromEnv({
        ...complete,
        'APPLE_CLIENT_IDS': 'me.heart-of.ios, me.heart.macos, me.heart-of.web=https://heart-of.me/apple',
      });

      expect(apple?.clients, {
        'me.heart-of.ios': null,
        'me.heart.macos': null,
        'me.heart-of.web': 'https://heart-of.me/apple',
      });
    });

    // Half a key signs nothing, and reading it as "Apple is configured" would
    // turn a deployment mistake into a no-op nobody notices.
    for (final missing in complete.keys) {
      test('is null without $missing', () {
        expect(AppleConfig.fromEnv({...complete}..remove(missing)), isNull);
      });

      test('is null when $missing is blank', () {
        expect(AppleConfig.fromEnv({...complete, missing: ''}), isNull);
      });
    }
  });
}
