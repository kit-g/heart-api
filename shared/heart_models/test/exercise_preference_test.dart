import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ExercisePreferenceField.fromString', () {
    for (final (raw, expected) in <(String, ExercisePreferenceField)>[
      ('unitSystem', .unitSystem),
      ('restTimer', .restTimer),
    ]) {
      test('parses $raw', () {
        expect(ExercisePreferenceField.fromString(raw), expected);
      });
    }

    for (final raw in <String?>[null, '', 'unit_system', 'rest_timer', 'chartType']) {
      test('throws on $raw', () {
        expect(() => ExercisePreferenceField.fromString(raw), throwsArgumentError);
      });
    }
  });

  group('ExercisePreferenceField column matches the DB column', () {
    for (final (field, column) in <(ExercisePreferenceField, String)>[
      (.unitSystem, 'unit_system'),
      (.restTimer, 'rest_timer'),
    ]) {
      test('${field.name} -> $column', () {
        expect(field.column, column);
      });
    }
  });

  group('ExercisePreference.fromJson', () {
    test('parses a full body', () {
      final pref = ExercisePreference.fromJson({
        'exerciseId': 'e-1',
        'unitSystem': 'metric',
        'restTimer': 90,
      });

      expect(pref.exerciseId, 'e-1');
      expect(pref.unitSystem, MeasurementUnit.metric);
      expect(pref.restTimer, 90);
    });

    test('parses a unit-only body', () {
      final pref = ExercisePreference.fromJson({
        'exerciseId': 'e-1',
        'unitSystem': 'imperial',
      });

      expect(pref.unitSystem, MeasurementUnit.imperial);
      expect(pref.restTimer, isNull);
    });

    test('parses a timer-only body', () {
      final pref = ExercisePreference.fromJson({
        'exerciseId': 'e-1',
        'restTimer': 120,
      });

      expect(pref.unitSystem, isNull);
      expect(pref.restTimer, 120);
    });

    test('rejects a body with nothing to update', () {
      expect(() => ExercisePreference.fromJson({'exerciseId': 'e-1'}), throwsArgumentError);
    });

    for (final (label, json) in <(String, Map)>[
      ('a missing exercise id', {'restTimer': 90}),
      ('an empty exercise id', {'exerciseId': '', 'restTimer': 90}),
      ('a non-string exercise id', {'exerciseId': 1, 'restTimer': 90}),
    ]) {
      test('rejects $label', () {
        expect(() => ExercisePreference.fromJson(json), throwsArgumentError);
      });
    }

    for (final unit in <Object>['kg', 'Metric', 1]) {
      test('rejects unit system $unit', () {
        expect(
          () => ExercisePreference.fromJson({'exerciseId': 'e-1', 'unitSystem': unit}),
          throwsArgumentError,
        );
      });
    }

    for (final timer in <Object>[0, -30, 90.5, '90']) {
      test('rejects rest timer $timer', () {
        expect(
          () => ExercisePreference.fromJson({'exerciseId': 'e-1', 'restTimer': timer}),
          throwsArgumentError,
        );
      });
    }
  });

  group('toMap', () {
    test('serialises the unit as its wire name', () {
      final pref = ExercisePreference(
        exerciseId: 'e-1',
        unitSystem: MeasurementUnit.metric,
        restTimer: 90,
      );

      expect(pref.toMap(), {'exerciseId': 'e-1', 'unitSystem': 'metric', 'restTimer': 90});
    });

    test('omits absent fields', () {
      final pref = ExercisePreference(exerciseId: 'e-1', restTimer: 60);

      expect(pref.toMap(), {'exerciseId': 'e-1', 'restTimer': 60});
    });

    test('round-trips through fromJson', () {
      final pref = ExercisePreference(
        exerciseId: 'e-1',
        unitSystem: MeasurementUnit.imperial,
        restTimer: 180,
      );

      final parsed = ExercisePreference.fromJson(pref.toMap());

      expect(parsed.exerciseId, pref.exerciseId);
      expect(parsed.unitSystem, pref.unitSystem);
      expect(parsed.restTimer, pref.restTimer);
    });
  });
}
