import 'package:heart/core/request.dart';
import 'package:heart/models/errors.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

/// Locks the body-decoding contract of `Request.json()`: an
/// `application/json` body parses, anything else is the client's mistake
/// (415), not a missing server feature (501).
void main() {
  test('an application/json body decodes to a map', () async {
    final request = jsonRequest(body: {'a': 1});
    expect(await request.json(), {'a': 1});
  });

  test('a non-JSON body throws UnsupportedMediaType', () {
    final request = RequestInternal.create(
      Method.post,
      Uri.parse('http://localhost/'),
      Object(),
      body: Body.fromString('plain text', mimeType: MimeType.plainText),
    );
    expect(request.json, throwsA(isA<UnsupportedMediaType>()));
  });

  test('a bodiless request throws UnsupportedMediaType', () {
    expect(bareRequest().json, throwsA(isA<UnsupportedMediaType>()));
  });

  group('locale resolution', () {
    const supported = ['en', 'en_CA', 'ru', 'es'];

    String resolve(String? acceptLanguage) {
      final request = bareRequest(
        extraHeaders: acceptLanguage == null ? const {} : {'accept-language': acceptLanguage},
      );
      return request.locale(supported, 'en');
    }

    test('no header falls back to the default', () {
      expect(resolve(null), 'en');
    });

    test('an exact tag matches, BCP-47 normalized', () {
      expect(resolve('en-CA'), 'en_CA');
      expect(resolve('ru'), 'ru');
    });

    test('the highest-quality supported language wins', () {
      expect(resolve('ru;q=0.8, es;q=0.9'), 'es');
    });

    test('a regional tag truncates to its supported base language', () {
      expect(resolve('es-MX'), 'es');
      expect(resolve('es-AR, en;q=0.5'), 'es');
    });

    test('a bare language matches a supported regional variant', () {
      final request = bareRequest(extraHeaders: {'accept-language': 'en'});
      expect(request.locale(['en_CA', 'ru'], 'ru'), 'en_CA');
    });

    test('an unsupported language falls through to the next candidate', () {
      expect(resolve('fr-FR, ru;q=0.7'), 'ru');
    });

    test('nothing acceptable falls back to the default', () {
      expect(resolve('fr-FR, de;q=0.9'), 'en');
    });
  });
}
