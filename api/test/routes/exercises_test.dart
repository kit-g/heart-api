import 'dart:convert';

import 'package:heart/models/errors.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/exercises.dart`, driven through the real
/// app. The exercise services return plain maps, so stubs stay trivial and the
/// focus is the handler glue: locale/owned query parsing, the required-field
/// validation on create, and path-parameter capture on update.
void main() {
  late AppHarness app;

  setUp(() async {
    app = await AppHarness.start();
    when(app.config.supportedLocales).thenReturn(const ['en']);
    when(app.config.defaultLocale).thenReturn('en');
  });

  tearDown(() => app.stop());

  group('GET /exercises', () {
    test('returns the library and threads userId + owned flag to the service', () async {
      when(
        app.db.getExercises(any, locale: anyNamed('locale'), owned: anyNamed('owned')),
      ).thenAnswer((_) async => {'squat': <String, dynamic>{}});

      final res = await app.send('GET', '/exercises?owned=true');
      expect(res.status, 200);
      expect(jsonDecode(res.body), containsPair('squat', anything));
      verify(app.db.getExercises('u1', locale: 'en', owned: true)).called(1);
    });

    test('defaults owned to false when the query flag is absent', () async {
      when(
        app.db.getExercises(any, locale: anyNamed('locale'), owned: anyNamed('owned')),
      ).thenAnswer((_) async => <String, dynamic>{});

      await app.send('GET', '/exercises');
      verify(app.db.getExercises('u1', locale: 'en', owned: false)).called(1);
    });
  });

  group('POST /exercises', () {
    test('creates an exercise from a valid body', () async {
      when(
        app.db.createExercise(
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          category: anyNamed('category'),
          target: anyNamed('target'),
          instructions: anyNamed('instructions'),
        ),
      ).thenAnswer((_) async => {'id': 'e1', 'name': 'Squat', 'created': true});

      final res = await app.send(
        'POST',
        '/exercises',
        body: {
          'name': 'Squat',
          'category': 'legs',
          'target': 'quads',
        },
      );
      // A fresh custom row was actually inserted → 201, not the 200 an
      // idempotent replay resolves to (kit-g/heart-api#66).
      expect(res.status, 201);
      final decoded = jsonDecode(res.body);
      expect(decoded, containsPair('name', 'Squat'));
      expect(decoded, isNot(contains('created'))); // internal-only, never on the wire
      verify(
        app.db.createExercise(
          userId: 'u1',
          name: 'Squat',
          category: 'legs',
          target: 'quads',
          instructions: null,
        ),
      ).called(1);
    });

    test('an idempotent replay (created: false) responds 200, not 201', () async {
      when(
        app.db.createExercise(
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          category: anyNamed('category'),
          target: anyNamed('target'),
          instructions: anyNamed('instructions'),
        ),
      ).thenAnswer((_) async => {'id': 'e1', 'name': 'Squat', 'created': false});

      final res = await app.send(
        'POST',
        '/exercises',
        body: {
          'name': 'Squat',
          'category': 'legs',
          'target': 'quads',
        },
      );
      expect(res.status, 200);
      final decoded = jsonDecode(res.body);
      expect(decoded, containsPair('name', 'Squat'));
      expect(decoded, isNot(contains('created')));
    });

    test('an id belonging to another account is Forbidden with id_taken', () async {
      when(
        app.db.createExercise(
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          category: anyNamed('category'),
          target: anyNamed('target'),
          instructions: anyNamed('instructions'),
        ),
      ).thenThrow(const Forbidden(code: 'id_taken', reason: 'this id belongs to another account'));

      final res = await app.send(
        'POST',
        '/exercises',
        body: {
          'name': 'Squat',
          'category': 'legs',
          'target': 'quads',
        },
      );
      expect(res.status, 403);
      expect(jsonDecode(res.body), containsPair('code', 'id_taken'));
    });

    test('rejects a missing name / category / target with 400', () async {
      expect((await app.send('POST', '/exercises', body: {'category': 'legs', 'target': 'quads'})).status, 400);
      expect((await app.send('POST', '/exercises', body: {'name': 'Squat', 'target': 'quads'})).status, 400);
      expect((await app.send('POST', '/exercises', body: {'name': 'Squat', 'category': 'legs'})).status, 400);
      verifyNever(
        app.db.createExercise(
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          category: anyNamed('category'),
          target: anyNamed('target'),
          instructions: anyNamed('instructions'),
        ),
      );
    });
  });

  group('PUT /exercises/:exerciseId', () {
    test('captures the path id and forwards the patch fields', () async {
      when(
        app.db.updateExercise(
          userId: anyNamed('userId'),
          exerciseId: anyNamed('exerciseId'),
          category: anyNamed('category'),
          target: anyNamed('target'),
          instructions: anyNamed('instructions'),
          archived: anyNamed('archived'),
        ),
      ).thenAnswer((_) async => {'id': 'e1', 'archived': true});

      final res = await app.send('PUT', '/exercises/e1', body: {'archived': true});
      expect(res.status, 200);
      verify(
        app.db.updateExercise(
          userId: 'u1',
          exerciseId: 'e1',
          category: null,
          target: null,
          instructions: null,
          archived: true,
        ),
      ).called(1);
    });
  });
}
