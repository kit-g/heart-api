import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

const _template = '0198c1a2-b3c4-7d5e-8f60-718293a4b505';

Request req(Map<String, dynamic> body) => jsonRequest(body: body)..user = User(id: 'u1');

Matcher badRequest([String? code]) {
  final matcher = isA<BadRequest>();
  return throwsA(code == null ? matcher : matcher.having((e) => e.code, 'code', code));
}

void main() {
  group('SkipIn', () {
    test('reads the moment, the reason, the weather and the session', () async {
      final input = await SkipIn.fromRequest(
        req({
          'at': '2026-10-14T07:30:00Z',
          'reason': 'just_no',
          'weather': {'temperature': -3, 'humidity': 90, 'pressure': 1001.5, 'pressureTrend': -7},
          'templateId': _template,
        }),
      );
      expect(input.skip.reason, 'just_no');
      expect(input.skip.weather?.pressureTrend, -7);
      expect(input.skip.templateId, _template);
    });

    test('a session id that is not a v7 id reads as none', () async {
      final input = await SkipIn.fromRequest(req({'at': '2026-10-14T07:30:00Z', 'templateId': 'local-1'}));
      expect(input.skip.templateId, isNull);
    });

    test('rejects a misspelled reason and weather that is not weather', () async {
      await expectLater(
        SkipIn.fromRequest(req({'at': '2026-10-14T07:30:00Z', 'reason': 'Tired'})),
        badRequest('invalid_reason'),
      );
      for (final weather in [
        [],
        {'temperature': 'cold'},
        {'temperature': 70},
        {'pressure': 500},
        {'latitude': 43.6},
      ]) {
        await expectLater(
          SkipIn.fromRequest(req({'at': '2026-10-14T07:30:00Z', 'weather': weather})),
          badRequest('invalid_weather'),
          reason: '$weather',
        );
      }
    });

    test('the health snapshot never gets in', () async {
      await expectLater(
        SkipIn.fromRequest(req({'at': '2026-10-14T07:30:00Z', 'sleep': 5.5})),
        badRequest('health_data'),
      );
    });

    test('needs the moment', () async {
      await expectLater(SkipIn.fromRequest(req({'reason': 'busy'})), badRequest());
    });
  });
}
