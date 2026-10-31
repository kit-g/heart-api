import 'dart:convert';
import 'dart:io';

import 'package:heart/globals/globals.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/lens.dart';
import 'package:heart/models/library.dart';
import 'package:heart/models/me.dart';
import 'package:heart/models/shape_overrides.dart';
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

Map<String, dynamic> _fixture() {
  return jsonDecode(File('test/compatibility/mobile_1_13/workout-save.json').readAsStringSync())
      as Map<String, dynamic>;
}

void main() {
  test('the generator reads every toMap() a route answers, or an override says it', () async {
    final generated = await generator.generate(Directory.current.path);
    expect(generated.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('every route is in the spec, with what it answers', () {
    final paths = meOpenApi()['paths'] as Map<String, Object?>;
    final operations = [for (final verbs in paths.values) ...(verbs as Map).values.cast<Map>()];
    expect(operations, hasLength(meRoutes.length));
    for (final operation in operations) {
      expect((operation['responses'] as Map).keys, contains('200'), reason: '${operation['operationId']}');
    }
  });

  test('a path parameter of the route is one its input reads', () {
    final paths = meOpenApi()['paths'] as Map<String, Object?>;
    for (final MapEntry(:key, :value) in paths.entries) {
      final named = RegExp(r'\{(\w+)\}').allMatches(key).map((match) => match[1]).toSet();
      final read = [
        for (final parameter in ((value as Map)['get'] as Map)['parameters'] as List? ?? const [])
          if ((parameter as Map)['in'] == 'path') parameter['name'],
      ];
      expect(read.toSet(), named, reason: key);
    }
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

  group('what the API assembles conforms to its shape', () {
    test('a balance, its pairs and their sides', () {
      final balance = MeBalance.fold(
        LensWindow.resolve(weekStart: DateTime.monday, to: DateTime.utc(2026, 10, 15)),
        const [],
        content: {
          'pairs': [
            {
              'key': 'push_pull',
              'left': {
                'key': 'push',
                'name': {'en': 'Push'},
                'patterns': ['horizontal_press'],
              },
              'right': {
                'key': 'pull',
                'patterns': ['horizontal_row'],
              },
            },
          ],
        },
        locale: 'en',
      );
      expect((balance.toMap()['pairs'] as List), hasLength(1));
      expect(meBalanceShape.check(balance.toMap(), 'body'), isEmpty);
    });

    test('goal progress, with a period and without', () {
      final progress = MeGoalProgress.measure(
        [
          Goal.fromJson({'id': 'g-1', 'metric': 'workouts', 'cadence': 'week', 'stages': const []}),
          Goal.fromJson({
            'id': 'g-2',
            'metric': 'workouts',
            'stages': [
              {'target': 10},
            ],
          }),
        ],
        now: DateTime.utc(2026, 10, 15),
        weekStart: DateTime.monday,
      );
      expect((progress.toMap()['goals'] as List), hasLength(2));
      expect(meGoalProgressShape.check(progress.toMap(), 'body'), isEmpty);
    });

    test('the custom exercises, as the query writes them', () {
      final response = ExerciseResponse(
        exerciseLibrary: {
          'exercises': [
            {
              'id': 'e-1',
              'key': null,
              'own': true,
              'name': 'Pushdown',
              'asset': null,
              'health': null,
              'target': 'Other',
              'aliases': const <String>[],
              'muscles': null,
              'archived': false,
              'category': 'Machine',
              'movement': null,
              'thumbnail': null,
              'validated': null,
              'rest_timer': 90,
              'unit_system': null,
              'instructions': null,
            },
          ],
          'glossary': {
            'db': {
              'words': ['dumbbell'],
            },
          },
        },
      );
      expect(customExercisesShape.check(response.toMap(), 'body'), isEmpty);
      expect(customExercisesShape.check({'exercises': const [], 'heartRate': 1}, 'body'), [
        'body.glossary: required by CustomExercises, missing',
        'body.heartRate: not in CustomExercises',
      ]);
    });

    test('a library program\'s summary stays open for what a later library adds', () {
      const body = LibraryResponse({
        'programs': [
          {'key': 'walk', 'name': 'Walk', 'perWeek': 3, 'later': true},
        ],
      });
      expect(libraryProgramsShape.check(body.toMap(), 'body'), isEmpty);
      expect(
        libraryProgramsShape.check({
          'programs': [
            {'key': 'walk'},
          ],
        }, 'body'),
        ['body.programs[0].name: required by LibraryProgramSummary, missing'],
      );
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
}
