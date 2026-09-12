import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/exercise_preferences.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';
import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _exerciseId = '019def00-0000-7000-8000-000000000001';

void main() {
  late MockApiExercisePreferenceService service;

  setUp(() {
    service = MockApiExercisePreferenceService();
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..exercisePreferenceService = service;
  }

  group('getExercisePreferences', () {
    test('returns the envelope with the service’s items', () async {
      final prefs = [
        ExercisePreference(exerciseId: _exerciseId, unitSystem: MeasurementUnit.imperial, restTimer: 90),
        ExercisePreference(exerciseId: '019def00-0000-7000-8000-000000000002', restTimer: 120),
      ];
      when(service.getExercisePreferences(any)).thenAnswer((_) async => prefs);

      final req = wire(bareRequest(method: Method.get, path: '/exercise-preferences'));

      final result = await getExercisePreferences(req);
      expect(result.preferences, prefs);
      verify(service.getExercisePreferences(_meId)).called(1);

      // Parity: every item must round-trip through ExercisePreference.fromJson
      // — this is the whole point of the read, since the app parses it that way.
      for (final pref in result.preferences) {
        final roundTripped = ExercisePreference.fromJson(pref.toMap());
        expect(roundTripped.exerciseId, pref.exerciseId);
        expect(roundTripped.unitSystem, pref.unitSystem);
        expect(roundTripped.restTimer, pref.restTimer);
      }
    });

    test('returns an empty envelope when the user has no preferences', () async {
      when(service.getExercisePreferences(any)).thenAnswer((_) async => const []);

      final req = wire(bareRequest(method: Method.get, path: '/exercise-preferences'));

      final result = await getExercisePreferences(req);
      expect(result.preferences, isEmpty);
    });
  });

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

    test('unpins only the note for the note field', () async {
      when(service.clearPreference(any, any, any)).thenAnswer((_) async {});

      final req = wire(bareRequest(method: Method.delete, path: '/exercise-preferences/$_exerciseId'));

      await expectLater(
        deleteExercisePreferenceById(req, _exerciseId, ExercisePreferenceField.note),
        throwsA(isA<NoContent>()),
      );
      verify(service.clearPreference(_exerciseId, _meId, ExercisePreferenceField.note)).called(1);
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

  group('GET /exercise-preferences (auth)', () {
    late AppHarness app;

    setUp(() async => app = await AppHarness.start());
    tearDown(() => app.stop());

    test('rejects an anonymous Firebase account (403 anonymous_account)', () async {
      final res = await app.send('GET', '/exercise-preferences', token: AppHarness.anonymousToken);
      expect(res.status, 403);
      expect(res.body, contains('anonymous_account'));
      verifyNever(app.db.getExercisePreferences(any));
    });

    test('rejects a missing token (401)', () async {
      final res = await app.send('GET', '/exercise-preferences', token: null);
      expect(res.status, 401);
      verifyNever(app.db.getExercisePreferences(any));
    });
  });

  group('POST /exercise-preferences — unreferenceable exercise (heart-api#74)', () {
    late AppHarness app;

    setUp(() async => app = await AppHarness.start());
    tearDown(() => app.stop());

    test('answers 404 unknown_exercise, not 500', () async {
      // What the db layer raises when the id is neither the caller's own custom
      // nor a library exercise. The incident was this reaching the client as
      // `500 server_error`, which the replay could not tell from an outage.
      when(app.db.savePreference(any, any)).thenThrow(
        const NotFound(type: 'Exercise', id: '01a07dfe-0bf2-7d18-a1fa-79abe2a92472', code: 'unknown_exercise'),
      );

      final res = await app.send(
        'POST',
        '/exercise-preferences',
        body: {'exerciseId': '01a07dfe-0bf2-7d18-a1fa-79abe2a92472', 'unitSystem': 'metric'},
      );

      expect(res.status, 404);
      expect(res.body, contains('"code":"unknown_exercise"'));
    });
  });
}
