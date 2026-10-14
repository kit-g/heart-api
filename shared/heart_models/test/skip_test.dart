import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('TrainingSkip', () {
    test('round-trips the wire shape', () {
      final json = {
        'id': 's1',
        'at': '2026-10-14T07:30:00.000Z',
        'reason': 'tired',
        'weather': {'temperature': 4.5, 'humidity': 80, 'pressure': 1003, 'pressureTrend': -6},
        'templateId': 't1',
        'programId': 'p1',
      };
      expect(TrainingSkip.fromJson(json).toMap(), json);
    });

    test('reads a row', () {
      final skip = TrainingSkip.fromRow({
        'id': 's1',
        'at': DateTime.utc(2026, 10, 14),
        'weather': {'pressure': 998},
        'template_id': 't1',
      });
      expect(skip.weather?.pressure, 998);
      expect(skip.templateId, 't1');
      expect(skip.reason, isNull);
    });

    test('a bare skip is just the moment', () {
      expect(TrainingSkip(at: DateTime.utc(2026, 10, 14)).toMap(), {'at': '2026-10-14T00:00:00.000Z'});
    });
  });

  group('Weather', () {
    test('keeps a field this build does not know', () {
      final weather = Weather.fromJson(const {'temperature': 20, 'uvIndex': 3});
      expect(weather.toMap(), {'uvIndex': 3, 'temperature': 20});
    });

    test('empty when nothing was measured', () {
      expect(Weather().isEmpty, isTrue);
      expect(TrainingSkip(at: DateTime.utc(2026), weather: Weather()).toMap().containsKey('weather'), isFalse);
    });
  });

  group('AccountSummary', () {
    test('counts programs, their history and skips', () {
      final summary = AccountSummary.fromJson(const {
        'collections': {
          'programs': {'count': 2},
          'programActions': {'count': 3},
          'programBases': {'count': 4},
          'skips': {'count': 5, 'latestId': 's9'},
        },
      });
      expect(summary.total, 14);
      expect(summary[.skips].latestId, 's9');
    });
  });
}
