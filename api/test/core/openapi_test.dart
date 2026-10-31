import 'dart:convert';
import 'dart:io';

import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/core/openapi/shape.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/me.dart';
import 'package:heart/models/shapes.g.dart';
import 'package:heart/routes/me_index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../../tool/openapi/shapes.dart' as generator;
import '../../tool/openapi/spec.dart';
import '../helpers/request.dart';
import '../mocks.mocks.dart';

/// The committed spec: a change to what `/me` declares shows up in review as
/// a diff of this file. `UPDATE_OPENAPI=1 dart test test/core/openapi_test.dart`
/// rewrites it.
final _golden = File('openapi/me.json');

Map<String, dynamic> _fixture() {
  return jsonDecode(File('test/compatibility/mobile_1_13/workout-save.json').readAsStringSync())
      as Map<String, dynamic>;
}

void main() {
  test('the committed spec is the one meRoutes declares', () {
    final spec = const JsonEncoder.withIndent('  ').convert(meOpenApi());
    if (Platform.environment['UPDATE_OPENAPI'] == '1') _golden.writeAsStringSync('$spec\n');
    expect('$spec\n', _golden.readAsStringSync(), reason: 'run with UPDATE_OPENAPI=1 to accept the change');
  });

  test('the committed shapes are the ones the toMap()s write', () async {
    final generated = await generator.generate(Directory.current.path);
    expect(generated.errors, isEmpty);
    expect(
      generated.source,
      File(generator.generatedPath).readAsStringSync(),
      reason: 'run `dart run tool/openapi/shapes.dart`',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('every route is in the spec, and says when it is not declared yet', () {
    final paths = meOpenApi()['paths'] as Map<String, Object?>;
    final operations = [for (final verbs in paths.values) ...(verbs as Map).values.cast<Map>()];
    expect(operations, hasLength(meRoutes.length));
    expect(operations.where((operation) => operation['x-undeclared'] == true), hasLength(lessThan(meRoutes.length)));
  });

  group('the shared models conform to the shapes read from their toMap()s', () {
    test('a template, with its folder and exercises', () {
      final template = Template.fromJson({
        'id': 't-1',
        'order': 3,
        'name': 'Push',
        'note': 'heavy',
        'programId': 'p-1',
        'joined': '2026-10-01T10:00:00.000Z',
        'folder': {'id': 'f-1', 'name': 'Strength', 'order': 1, 'templateCount': 2},
        'exercises': _fixture()['exercises'],
      });
      expect(templateShape.check(template.toMap(), 'body'), isEmpty);
    });

    test('a folder', () {
      final folder = TemplateFolder.fromJson({'id': 'f-1', 'name': 'Strength', 'order': 1, 'templateCount': 2});
      expect(templateFolderShape.check(folder.toMap(), 'body'), isEmpty);
    });

    test('a goal, plain and laddered', () {
      for (final json in <Map<String, dynamic>>[
        {'id': 'g-1', 'metric': 'workouts', 'cadence': 'week', 'stages': const []},
        {
          'id': 'g-2',
          'metric': 'sets',
          'muscle': 'chest',
          'cadence': 'week',
          'archived': true,
          'createdAt': '2026-10-01T10:00:00.000Z',
          'stages': [
            {'target': 10},
          ],
        },
      ]) {
        expect(goalShape.check(Goal.fromJson(json).toMap(), 'body'), isEmpty, reason: '$json');
      }
    });

    test('an anomaly, open and resolved', () {
      for (final extra in <Map<String, dynamic>>[
        const {},
        {
          'setId': 's-1',
          'exerciseId': 'e-1',
          'exerciseName': 'Bench',
          'typical': 60,
          'workoutStart': '2026-10-01T10:00:00.000Z',
          'resolvedAt': '2026-10-02T10:00:00.000Z',
        },
      ]) {
        final anomaly = Anomaly.fromJson({
          'id': 'a-1',
          'workoutId': 'w-1',
          'reason': 'weight',
          'observed': {'weight': 600},
          'status': 'pending',
          'detectedAt': '2026-10-01T11:00:00.000Z',
          ...extra,
        });
        expect(anomalyShape.check(anomaly.toMap(), 'body'), isEmpty, reason: '$extra');
      }
    });
  });

  group('a workout as /me writes it', () {
    late MockApiWorkoutService workouts;

    setUp(() => workouts = MockApiWorkoutService());

    Request request() {
      final config = MockAppConfig();
      when(config.cdnAssetUrl(any)).thenAnswer((call) => 'https://cdn.example/${call.positionalArguments.single}');
      return bareRequest(method: Method.get, path: '/me/workouts/x')
        ..user = User(id: 'u1')
        ..config = config
        ..workoutsService = workouts;
    }

    test('conforms to its shape, from the 1.13 compatibility fixture', () async {
      final workout = Workout.fromJson(_fixture());
      when(
        workouts.getWorkout(userId: 'u1', workoutId: workout.id, imageUrl: anyNamed('imageUrl')),
      ).thenAnswer((_) async => workout);

      final body = (await meRoutes[('/workouts/:workoutId', Method.get)]!.call(
        request(),
        path: {'workoutId': workout.id},
      ))!.toMap();

      expect(meWorkoutShape.check(body, 'body'), isEmpty);
      expect(body['images'], isEmpty);
    });

    test('a key the shape does not name fails the check, and so does a missing one', () {
      final json = MeWorkout(Workout.fromJson(_fixture())).toMap();
      expect(meWorkoutShape.check({...json, 'heartRate': 120}, 'body'), ['body.heartRate: not in MeWorkout']);
      expect(
        meWorkoutShape.check({...json}..remove('pauses'), 'body'),
        ['body.pauses: required by MeWorkout, missing'],
      );
    });

    test('an optional key a toMap() writes as null passes where its shape says nullable', () {
      final json = MeWorkout(Workout.fromJson(_fixture())).toMap();
      final exercise = {...(json['exercises'] as List).first as Map, 'rest': null};
      expect(workoutExerciseShape.check(exercise, 'exercise'), isEmpty);
      expect(
        workoutExerciseShape.check({...exercise, 'note': null}, 'exercise'),
        ['exercise.note: optional in WorkoutExercise, so left out when null, but written as null'],
      );
    });
  });

  test('a refusal the route does not declare fails while asserts are on', () {
    final endpoint = Endpoint.none<MeProfile>(
      (_) => throw const Forbidden(reason: 'no'),
      reply: .json(meProfileShape),
    );
    expect(() => endpoint.call(bareRequest()), throwsA(isA<AssertionError>()));
  });

  test('a declared refusal goes through as thrown', () {
    final endpoint = Endpoint.none<MeProfile>(
      (_) => throw const NotFound(type: 'profile', id: 'u1'),
      reply: .json(meProfileShape),
      errors: [const .notFound()],
    );
    expect(() => endpoint.call(bareRequest()), throwsA(isA<NotFound>()));
  });

  test('an object shape writes an optional key only when it has a value', () {
    final shape = Shape.object<({String? name})>('Named', {'name': .optional(.string, (it) => it.name)});
    expect(shape.encode((name: null)), isEmpty);
    expect(shape.encode((name: 'x')), {'name': 'x'});
  });
}
