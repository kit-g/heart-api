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
    test('upserts the unit preference for the requesting user', () async {
      when(
        service.saveUnitPreference(any, any),
      ).thenAnswer((i) async => i.positionalArguments[0] as ExercisePreference);

      final req = wire(
        jsonRequest(
          method: Method.post,
          path: '/exercise-preferences',
          body: {'exerciseId': _exerciseId, 'unitSystem': 'imperial'},
        ),
      );

      final result = await saveExercisePreference(req);
      expect(result.exerciseId, _exerciseId);
      expect(result.unitSystem, MeasurementUnit.imperial);

      final captured = verify(service.saveUnitPreference(captureAny, _meId)).captured.single as ExercisePreference;
      expect(captured.exerciseId, _exerciseId);
      expect(captured.unitSystem, MeasurementUnit.imperial);
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
      verifyNever(service.saveUnitPreference(any, any));
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
      verifyNever(service.saveUnitPreference(any, any));
    });
  });

  group('deleteExercisePreferenceById', () {
    test('clears the unit preference and returns NoContent', () async {
      when(service.deleteUnitPreference(any, any)).thenAnswer((_) async {});

      final req = wire(bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId'));

      await expectLater(deleteExercisePreferenceById(req, _exerciseId), throwsA(isA<NoContent>()));
      verify(service.deleteUnitPreference(_exerciseId, _meId)).called(1);
    });
  });
}
