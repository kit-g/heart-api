import 'package:heart/globals/firebase.dart';
import 'package:openid_client/openid_client.dart';
import 'package:test/test.dart';

void main() {
  group('isAnonymousAccount', () {
    test('true when firebase.sign_in_provider is anonymous', () {
      final claims = OpenIdClaims.fromJson({
        'sub': 'u1',
        'firebase': {'sign_in_provider': 'anonymous'},
      });

      expect(isAnonymousAccount(claims), isTrue);
    });

    test('false for a Google-signed token', () {
      final claims = OpenIdClaims.fromJson({
        'sub': 'u1',
        'firebase': {'sign_in_provider': 'google.com'},
      });

      expect(isAnonymousAccount(claims), isFalse);
    });

    test('false for an Apple-signed token', () {
      final claims = OpenIdClaims.fromJson({
        'sub': 'u1',
        'firebase': {'sign_in_provider': 'apple.com'},
      });

      expect(isAnonymousAccount(claims), isFalse);
    });

    test('false when there is no firebase claim at all', () {
      final claims = OpenIdClaims.fromJson({'sub': 'u1'});

      expect(isAnonymousAccount(claims), isFalse);
    });
  });
}
