import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  final created = DateTime.utc(2026, 10, 4, 12);

  group('ApiToken', () {
    test('round-trips through toMap and fromJson', () {
      final token = ApiToken(
        id: '019a0000-0000-7000-8000-000000000001',
        name: 'my sheet',
        purpose: ApiTokenPurpose.spreadsheet,
        hint: 'x9Qz',
        createdAt: created,
        lastUsedAt: created.add(const Duration(hours: 1)),
        expiresAt: created.add(const Duration(days: 365)),
      );

      final map = token.toMap();
      expect(map, {
        'id': '019a0000-0000-7000-8000-000000000001',
        'name': 'my sheet',
        'purpose': 'spreadsheet',
        'hint': 'x9Qz',
        'scopes': ['read'],
        'createdAt': '2026-10-04T12:00:00.000Z',
        'lastUsedAt': '2026-10-04T13:00:00.000Z',
        'expiresAt': '2027-10-04T12:00:00.000Z',
      });

      final back = ApiToken.fromJson(map);
      expect(back.purpose, ApiTokenPurpose.spreadsheet);
      expect(back.expiresAt, token.expiresAt);
      expect(back.revokedAt, isNull);
      expect(back, token);
    });

    test('omits what is absent', () {
      final map = ApiToken(id: 'a', name: 'n', hint: 'abcd', createdAt: created).toMap();
      expect(map.keys, unorderedEquals(['id', 'name', 'hint', 'scopes', 'createdAt']));
    });

    test('parses a database row', () {
      final token = ApiToken.fromRow({
        'id': 'a',
        'name': 'Home Assistant',
        'purpose': 'homeAutomation',
        'hint': 'abcd',
        'scopes': ['read'],
        'created_at': created,
        'last_used_at': null,
        'expires_at': null,
        'revoked_at': created,
      });
      expect(token.purpose, ApiTokenPurpose.homeAutomation);
      expect(token.revokedAt, created);
    });

    test('is active until revoked or expired', () {
      final live = ApiToken(id: 'a', name: 'n', hint: 'abcd', createdAt: created);
      expect(live.isActive(created), isTrue);

      final revoked = ApiToken(id: 'a', name: 'n', hint: 'abcd', createdAt: created, revokedAt: created);
      expect(revoked.isActive(created), isFalse);

      final expiring = ApiToken(
        id: 'a',
        name: 'n',
        hint: 'abcd',
        createdAt: created,
        expiresAt: created.add(const Duration(days: 1)),
      );
      expect(expiring.isActive(created), isTrue);
      expect(expiring.isActive(created.add(const Duration(days: 2))), isFalse);
    });
  });

  group('MintedApiToken', () {
    test('carries the secret beside the token fields', () {
      final minted = MintedApiToken(
        token: ApiToken(id: 'a', name: 'n', hint: 'abcd', createdAt: created),
        secret: 'hrt_secretabcd',
      );
      final map = minted.toMap();
      expect(map['secret'], 'hrt_secretabcd');
      expect(map['hint'], 'abcd');

      final back = MintedApiToken.fromJson(map);
      expect(back.secret, 'hrt_secretabcd');
      expect(back.token.id, 'a');
    });
  });

  group('enums', () {
    test('purpose parses wire values and rejects others', () {
      expect(ApiTokenPurpose.fromString('aiAssistant'), ApiTokenPurpose.aiAssistant);
      expect(() => ApiTokenPurpose.fromString('robot'), throwsArgumentError);
    });

    test('expiry parses year and never only', () {
      expect(ApiTokenExpiry.fromString('year'), ApiTokenExpiry.year);
      expect(ApiTokenExpiry.fromString('never'), ApiTokenExpiry.never);
      expect(() => ApiTokenExpiry.fromString('month'), throwsArgumentError);
    });
  });
}
