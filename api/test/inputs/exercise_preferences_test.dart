import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('ExercisePreferenceSaveIn — ArgumentError mapped to BadRequest', () {
    Future<ExercisePreferenceSaveIn> parse(Map<String, dynamic> body) =>
        ExercisePreferenceSaveIn.fromRequest(jsonRequest(body: body));

    test('parses unit + rest timer', () async {
      final pref = (await parse({'exerciseId': 'e1', 'unitSystem': 'imperial', 'restTimer': 90})).preference;
      expect(pref.exerciseId, 'e1');
      expect(pref.unitSystem, MeasurementUnit.imperial);
      expect(pref.restTimer, 90);
    });

    test('accepts a rest-timer-only body', () async {
      final pref = (await parse({'exerciseId': 'e1', 'restTimer': 120})).preference;
      expect(pref.unitSystem, isNull);
      expect(pref.restTimer, 120);
    });

    for (final (label, body) in <(String, Map<String, dynamic>)>[
      ('missing exerciseId', {'restTimer': 60}),
      ('invalid unit system', {'exerciseId': 'e1', 'unitSystem': 'furlongs'}),
      ('non-positive rest timer', {'exerciseId': 'e1', 'restTimer': 0}),
      ('no preference fields', {'exerciseId': 'e1'}),
    ]) {
      test('rejects a body with $label', () async {
        await expectLater(parse(body), throwsA(isA<BadRequest>()));
      });
    }
  });

  group('ExercisePreferenceDeleteQuery — pref query param', () {
    ExercisePreferenceDeleteQuery parse(Map<String, String> query) =>
        ExercisePreferenceDeleteQuery.fromRequest(bareRequest(method: Method.delete, query: query));

    for (final (raw, expected) in <(String, ExercisePreferenceField)>[
      ('unitSystem', ExercisePreferenceField.unitSystem),
      ('restTimer', ExercisePreferenceField.restTimer),
    ]) {
      test('parses pref=$raw', () {
        expect(parse({'pref': raw}).field, expected);
      });
    }

    test('rejects a missing pref', () {
      expect(() => parse({}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown pref', () {
      expect(() => parse({'pref': 'bogus'}), throwsA(isA<BadRequest>()));
    });
  });
}
