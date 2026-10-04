import 'dart:typed_data';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart/routes/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  late MockApiTokenService service;
  final created = DateTime.utc(2026, 10, 4);
  const tokenId = '019a0000-0000-7000-8000-000000000001';

  ApiToken stored({String hint = 'abcd', DateTime? expiresAt}) {
    return ApiToken(id: tokenId, name: 'my sheet', hint: hint, createdAt: created, expiresAt: expiresAt);
  }

  setUp(() => service = MockApiTokenService());

  group('createApiToken', () {
    Request build(Map<String, dynamic> body) {
      return jsonRequest(path: '/accounts/tokens', body: body)
        ..user = User(id: 'u1')
        ..apiTokenService = service;
    }

    void stubCreate(ApiToken? result) {
      when(
        service.createToken(
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          purpose: anyNamed('purpose'),
          expiresAt: anyNamed('expiresAt'),
          tokenHash: anyNamed('tokenHash'),
          hint: anyNamed('hint'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('mints a secret, stores only its hash and hint, returns it once', () async {
      stubCreate(stored());

      final result = await createApiToken(build({'name': 'my sheet', 'expiry': 'never', 'purpose': 'spreadsheet'}));

      expect(result, isA<Created>());
      final minted = (result as Created).value as MintedApiToken;
      expect(TokenSecret.looksValid(minted.secret), isTrue);

      final captured = verify(
        service.createToken(
          userId: 'u1',
          name: 'my sheet',
          purpose: ApiTokenPurpose.spreadsheet,
          expiresAt: null,
          tokenHash: captureAnyNamed('tokenHash'),
          hint: captureAnyNamed('hint'),
        ),
      ).captured;
      expect(captured[0] as Uint8List, TokenSecret.hash(minted.secret));
      expect(captured[1], minted.secret.substring(minted.secret.length - 4));
    });

    test('a year of expiry is computed on the server', () async {
      stubCreate(stored());

      await createApiToken(build({'name': 'n', 'expiry': 'year'}));

      final expiresAt =
          verify(
                service.createToken(
                  userId: 'u1',
                  name: 'n',
                  purpose: null,
                  expiresAt: captureAnyNamed('expiresAt'),
                  tokenHash: anyNamed('tokenHash'),
                  hint: anyNamed('hint'),
                ),
              ).captured.single
              as DateTime;
      final days = expiresAt.difference(DateTime.now().toUtc()).inDays;
      expect(days, inInclusiveRange(364, 365));
    });

    test('the cap is a 400 token_limit', () async {
      stubCreate(null);

      expect(
        () => createApiToken(build({'name': 'n', 'expiry': 'never'})),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'token_limit')),
      );
    });

    test('rejects a blank or missing name, a bad expiry and an unknown purpose', () {
      expect(() => createApiToken(build({'name': '  ', 'expiry': 'never'})), throwsA(isA<BadRequest>()));
      expect(() => createApiToken(build({'expiry': 'never'})), throwsA(isA<BadRequest>()));
      expect(() => createApiToken(build({'name': 'n', 'expiry': 'month'})), throwsA(isA<BadRequest>()));
      expect(
        () => createApiToken(build({'name': 'n', 'expiry': 'never', 'purpose': 'robot'})),
        throwsA(isA<BadRequest>()),
      );
      expect(
        () => createApiToken(build({'name': 'x' * (ApiToken.maxNameLength + 1), 'expiry': 'never'})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('listApiTokens', () {
    test('lists the caller\'s tokens without secrets', () async {
      when(service.listTokens('u1')).thenAnswer((_) async => [stored()]);

      final request = bareRequest(method: Method.get, path: '/accounts/tokens')
        ..user = User(id: 'u1')
        ..apiTokenService = service;
      final map = (await listApiTokens(request)).toMap();

      expect(map['tokens'], hasLength(1));
      expect((map['tokens'] as List).single, isNot(contains('secret')));
    });
  });

  group('revokeApiTokenById', () {
    Request build() {
      return bareRequest(method: Method.delete, path: '/accounts/tokens/$tokenId')
        ..user = User(id: 'u1')
        ..apiTokenService = service;
    }

    test('revokes the caller\'s token', () async {
      when(service.revokeToken(userId: 'u1', tokenId: tokenId)).thenAnswer((_) async => true);
      expect(() => revokeApiTokenById(build(), tokenId), throwsA(isA<NoContent>()));
    });

    test('someone else\'s or a missing token is a 404', () async {
      when(service.revokeToken(userId: 'u1', tokenId: tokenId)).thenAnswer((_) async => false);
      expect(() => revokeApiTokenById(build(), tokenId), throwsA(isA<NotFound>()));
    });

    test('a malformed id is a 404 without a query', () async {
      expect(() => revokeApiTokenById(build(), 'nope'), throwsA(isA<NotFound>()));
      verifyNever(service.revokeToken(userId: anyNamed('userId'), tokenId: anyNamed('tokenId')));
    });
  });
}
