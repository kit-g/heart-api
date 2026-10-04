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

  /// The device-only health rule as an enforced contract: every JSON route
  /// decodes through `json()`, so a health-shaped key is a 400 on all of them.
  group('health-shaped fields', () {
    Matcher rejects(String field) {
      return throwsA(
        isA<BadRequest>()
            .having((e) => e.code, 'code', 'health_data')
            .having((e) => e.reason, 'reason', startsWith(field)),
      );
    }

    test('a top-level health key is rejected', () {
      for (final key in ['heartRate', 'hrv', 'sleep', 'bodyMass', 'restingHeartRate', 'activeEnergy', 'steps']) {
        expect(jsonRequest(body: {'name': 'Push', key: 1}).json(), rejects(key), reason: key);
      }
    });

    test('casing and separators do not hide a key', () {
      for (final key in ['heart_rate', 'Heart-Rate', 'BODY_MASS', 'avgHeartRate', 'sleepMinutes', 'body_weight']) {
        expect(jsonRequest(body: {key: 1}).json(), rejects(key), reason: key);
      }
    });

    test('a nested key is rejected with its path', () {
      final body = {
        'exercises': [
          {
            'sets': [
              {'reps': 5},
            ],
          },
          {
            'sets': [
              {'reps': 5, 'heartRate': 150},
            ],
          },
        ],
      };
      expect(jsonRequest(body: body).json(), rejects('exercises[1].sets[0].heartRate'));
    });

    test('the workout fields the API does take pass', () async {
      final body = {
        'name': 'Push',
        'calories': 312.5,
        'note': 'slept badly, heart rate high',
        'exercises': [
          {
            'met': 6.0,
            'sets': [
              {'weight': 100, 'reps': 5, 'rpe': 8},
            ],
          },
        ],
      };
      expect(await jsonRequest(body: body).json(), body);
    });
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
