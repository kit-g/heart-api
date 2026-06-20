import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/exercise_preferences.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _exerciseId = '019def00-0000-7000-8000-000000000001';

void main() {
  late MockExercisePreferenceService service;

  setUp(() {
    service = MockExercisePreferenceService();
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..exercisePreferenceService = service;
  }

  group('saveExercisePreference', () {
    test('upserts unit + rest timer for the requesting user', () async {
      when(
        service.savePreference(any, any),
      ).thenAnswer((i) async => i.positionalArguments[0] as ExercisePreference);

      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId, 'unitSystem': 'imperial', 'restTimer': 90},
        ),
      );

      final result = await saveExercisePreference(req);
      expect(result.exerciseId, _exerciseId);
      expect(result.unitSystem, MeasurementUnit.imperial);
      expect(result.restTimer, 90);

      final captured = verify(service.savePreference(captureAny, _meId)).captured.single as ExercisePreference;
      expect(captured.unitSystem, MeasurementUnit.imperial);
      expect(captured.restTimer, 90);
    });

    test('accepts a rest-timer-only body (unit untouched)', () async {
      when(
        service.savePreference(any, any),
      ).thenAnswer((i) async => i.positionalArguments[0] as ExercisePreference);

      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId, 'restTimer': 120},
        ),
      );

      final result = await saveExercisePreference(req);
      expect(result.unitSystem, isNull);
      expect(result.restTimer, 120);
    });

    test('rejects an invalid unitSystem with BadRequest', () {
      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId, 'unitSystem': 'furlongs'},
        ),
      );

      expect(() => saveExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.savePreference(any, any));
    });

    test('rejects a non-positive restTimer with BadRequest', () {
      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId, 'restTimer': 0},
        ),
      );

      expect(() => saveExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.savePreference(any, any));
    });

    test('rejects a body with no pref fields with BadRequest', () {
      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId},
        ),
      );

      expect(() => saveExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.savePreference(any, any));
    });

    test('rejects a missing exerciseId with BadRequest', () {
      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'unitSystem': 'metric'},
        ),
      );

      expect(() => saveExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.savePreference(any, any));
    });
  });

  group('deleteExercisePreferenceById', () {
    test('clears only the unit pref for the unitSystem field', () async {
      when(service.clearPreference(any, any, any)).thenAnswer((_) async {});

      final req = wire(bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId'));

      await expectLater(
        deleteExercisePreferenceById(req, _exerciseId, ExercisePreferenceField.unitSystem),
        throwsA(isA<NoContent>()),
      );
      verify(service.clearPreference(_exerciseId, _meId, ExercisePreferenceField.unitSystem)).called(1);
    });

    test('clears only the rest timer for the restTimer field', () async {
      when(service.clearPreference(any, any, any)).thenAnswer((_) async {});

      final req = wire(bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId'));

      await expectLater(
        deleteExercisePreferenceById(req, _exerciseId, ExercisePreferenceField.restTimer),
        throwsA(isA<NoContent>()),
      );
      verify(service.clearPreference(_exerciseId, _meId, ExercisePreferenceField.restTimer)).called(1);
    });
  });

  group('deleteExercisePreference (pref query param)', () {
    test('rejects a missing pref with BadRequest', () {
      final req = wire(bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId'));
      expect(() => deleteExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.clearPreference(any, any, any));
    });

    test('rejects an unknown pref with BadRequest', () {
      final req = wire(
        bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId', query: {'pref': 'bogus'}),
      );
      expect(() => deleteExercisePreference(req), throwsA(isA<BadRequest>()));
      verifyNever(service.clearPreference(any, any, any));
    });
  });
}
