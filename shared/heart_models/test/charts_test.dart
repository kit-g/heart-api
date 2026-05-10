import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ChartPreference', () {
    test('ChartPreference.fromRow works with topSetWeight', () {
      final row = {
        'id': '1',
        'type': 'topSetWeight',
        'data': '{"exerciseName": "Bench Press"}'
      };
      final pref = ChartPreference.fromRow(row);

      expect(pref.id, '1');
      expect(pref.type, ChartPreferenceType.topSetWeight);
      expect(pref.exerciseName, 'Bench Press');
    });

    test('ChartPreference.fromRow works with null data', () {
      final row = {
        'id': '2',
        'type': 'maxConsecutiveReps',
        'data': null
      };
      final pref = ChartPreference.fromRow(row);

      expect(pref.id, '2');
      expect(pref.type, ChartPreferenceType.maxConsecutiveReps);
      expect(pref.data, isNull);
    });

    test('ChartPreference.topSetWeight factory works', () {
      final pref = ChartPreference.exercise('Squat', .topSetWeight);

      expect(pref.id, isNull);
      expect(pref.type, ChartPreferenceType.topSetWeight);
      expect(pref.exerciseName, 'Squat');
    });

    test('toRow works', () {
      final pref = ChartPreference.exercise('Deadlift', .topSetWeight);
      final row = pref.toRow();

      expect(row['id'], isNull);
      expect(row['type'], 'topSetWeight');
      expect(row['data'], '{"exerciseName":"Deadlift"}');
    });

    test('copyWith works', () {
      final pref = ChartPreference.exercise('Bench Press', .topSetWeight);
      final updated = pref.copyWith(id: 'new-id');

      expect(updated.id, 'new-id');
      expect(updated.type, pref.type);
      expect(updated.exerciseName, pref.exerciseName);
    });
  });

  group('ChartPreferenceType', () {
    test('fromString works', () {
      expect(ChartPreferenceType.fromString('topSetWeight'), ChartPreferenceType.topSetWeight);
      expect(ChartPreferenceType.fromString('maxConsecutiveReps'), ChartPreferenceType.maxConsecutiveReps);
    });

    test('fromString throws on invalid value', () {
      expect(() => ChartPreferenceType.fromString('invalid'), throwsArgumentError);
    });
  });
}
