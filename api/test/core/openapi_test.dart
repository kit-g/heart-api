import 'dart:convert';
import 'dart:io';

import 'package:heart/core/docs_router.dart';
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
import '../helpers/app_harness.dart';
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

  group('the docs router', () {
    test('serves the spec and Swagger UI without a token where the environment publishes them', () async {
      final app = await AppHarness.start(docs: true);
      addTearDown(app.stop);

      final spec = await app.send('GET', '/docs/me.json', token: null);
      expect(spec.status, 200);
      expect(jsonDecode(spec.body), meOpenApi());
      final ui = await app.send('GET', '/docs', token: null);
      expect(ui.status, 200);
      expect(ui.body, contains('SwaggerUIBundle'));
    });

    test('is not there where it does not', () async {
      final app = await AppHarness.start();
      addTearDown(app.stop);

      expect((await app.send('GET', '/docs/me.json', token: null)).status, 404);
    });
  });
}
