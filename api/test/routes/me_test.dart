import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/lens.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/routes/me.dart';
import 'package:heart/routes/me_index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  late MockApiProfileService profiles;
  late MockApiWorkoutService workouts;
  late MockExerciseService exercises;
  late MockIdempotentGoalService goals;
  late MockApiAnomalyService anomalies;
  late MockAppConfig config;

  setUp(() {
    profiles = MockApiProfileService();
    workouts = MockApiWorkoutService();
    exercises = MockExerciseService();
    goals = MockIdempotentGoalService();
    anomalies = MockApiAnomalyService();
    when(
      anomalies.getPendingAnomalies(userId: anyNamed('userId'), from: anyNamed('from'), to: anyNamed('to')),
    ).thenAnswer((_) async => []);
    config = MockAppConfig();
    when(config.supportedLocales).thenReturn(['en']);
    when(config.defaultLocale).thenReturn('en');
  });

  /// [route] of `/me` as the router runs it: input read, result encoded and
  /// held to its shape.
  Future<Model> serve(String route, Request request, {Map<String, String> path = const {}}) async {
    return (await meRoutes[(route, Method.get)]!.call(request, path: path))!;
  }

  Request build(String path, {Map<String, String> query = const {}}) {
    return bareRequest(method: Method.get, path: path, query: query)
      ..user = User(id: 'u1')
      ..config = config
      ..profileService = profiles
      ..workoutsService = workouts
      ..exerciseService = exercises
      ..goalService = goals
      ..anomalyService = anomalies;
  }

  test('getMe is a 404 when the account has no profile', () {
    when(profiles.getProfile('u1')).thenAnswer((_) async => null);
    expect(() => getMe(build('/me')), throwsA(isA<NotFound>()));
  });

  test('getMyWorkoutById rejects a malformed id without a query', () {
    expect(
      () => serve('/workouts/:workoutId', build('/me/workouts/x'), path: {'workoutId': 'x'}),
      throwsA(isA<NotFound>()),
    );
    verifyNever(
      workouts.getWorkout(userId: anyNamed('userId'), workoutId: anyNamed('workoutId'), imageUrl: anyNamed('imageUrl')),
    );
  });

  test('getMyExercises lists only the caller\'s own exercises, whatever the query says', () async {
    when(exercises.getExercises('u1', locale: 'en', owned: true)).thenAnswer((_) async => {});

    await getMyExercises(build('/me/exercises', query: {'owned': 'false'}));

    verify(exercises.getExercises('u1', locale: 'en', owned: true)).called(1);
  });

  test('getMyGoals reads the caller\'s own goals', () async {
    when(goals.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1')).thenAnswer((_) async => []);

    await serve('/goals', build('/me/goals'));

    verify(goals.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1')).called(1);
  });

  group('exportMe', () {
    late MockApiTokenService tokens;
    late MockExportStorage storage;

    setUp(() {
      tokens = MockApiTokenService();
      storage = MockExportStorage();
      when(profiles.getProfile('u1')).thenAnswer((_) async => User(id: 'u1'));
      when(
        workouts.getWorkouts(
          userId: 'u1',
          targetUserId: 'u1',
          imageUrl: anyNamed('imageUrl'),
          cursor: anyNamed('cursor'),
          limit: 100,
        ),
      ).thenAnswer((_) async => const Page(items: [], hasMore: false));
    });

    Request exportRequest([Map<String, String> query = const {'format': 'strong'}]) {
      return build('/me/export', query: query)
        ..apiTokenService = tokens
        ..exportStorage = storage;
    }

    test('a small export is the body, as a Strong CSV download', () async {
      when(tokens.claimExport('u1')).thenAnswer((_) async => null);

      final result = await serve('/export', exportRequest());

      expect(result, isA<Download>());
      final download = result as Download;
      expect(utf8.decode(download.bytes), startsWith('Date,Workout Name,Duration,Exercise Name,Set Order'));
      expect(download.filename, 'heart-strong.csv');
      verifyZeroInteractions(storage);
    });

    test('a large one goes through storage and a 303', () async {
      when(tokens.claimExport('u1')).thenAnswer((_) async => null);
      final link = Uri.parse('https://bucket.example/exports/x/heart-strong.csv?sig=1');
      when(
        storage.stash(key: anyNamed('key'), bytes: anyNamed('bytes'), mimeType: 'text/csv'),
      ).thenAnswer((_) async => link);

      final result = await exportMe(
        exportRequest(),
        ExportQuery.read(.values(const {'format': 'strong'})),
        inlineLimit: 10,
      );

      expect((result as SeeOther).location, link);
      final key =
          verify(
                storage.stash(key: captureAnyNamed('key'), bytes: anyNamed('bytes'), mimeType: 'text/csv'),
              ).captured.single
              as String;
      expect(key, startsWith('exports/'));
    });

    test('a second export the same day is a 429 export_limit', () async {
      when(tokens.claimExport('u1')).thenAnswer(
        (_) async => DateTime.now().toUtc().subtract(const Duration(hours: 23)),
      );

      expect(
        () => serve('/export', exportRequest()),
        throwsA(
          isA<TooManyRequests>()
              .having((e) => e.code, 'code', 'export_limit')
              .having((e) => e.retryAfter, 'retryAfter', inInclusiveRange(3500, 3600)),
        ),
      );
    });

    test('the format is required and must be known, before the allowance is spent', () {
      expect(() => serve('/export', exportRequest(const {})), throwsA(isA<BadRequest>()));
      expect(() => serve('/export', exportRequest(const {'format': 'hevy'})), throwsA(isA<BadRequest>()));
      verifyNever(tokens.claimExport(any));
    });
  });

  group('changes and records', () {
    test('a since that is not a cursor from the feed is a 400', () {
      expect(
        () => serve('/workouts/changes', build('/me/workouts/changes', query: {'since': 'garbage'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('a malformed exerciseId is a 400', () {
      expect(() => serve('/records', build('/me/records', query: {'exerciseId': 'x'})), throwsA(isA<BadRequest>()));
    });

    test('a window that is not dates, or runs backwards, is a 400', () {
      expect(() => serve('/records', build('/me/records', query: {'from': 'last year'})), throwsA(isA<BadRequest>()));
      expect(
        () => serve('/records', build('/me/records', query: {'from': '2026-02-01', 'to': '2026-01-01'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('records read the window: a date is that day from midnight UTC, a moment as written', () async {
      when(
        workouts.getRecordSets(
          userId: 'u1',
          exerciseId: null,
          from: DateTime.utc(2026),
          to: DateTime.utc(2026, 6, 1, 12),
        ),
      ).thenAnswer((_) async => []);

      final records = await serve(
        '/records',
        build('/me/records', query: {'from': '2026-01-01', 'to': '2026-06-01T12:00:00Z'}),
      );

      expect(records.toMap()['records'], isEmpty);
    });

    test('records fold per exercise, by name, leaving out exercises with nothing measured', () async {
      RecordSet set(double? weight, int? reps) => RecordSet(
        weight: weight,
        reps: reps,
        duration: null,
        distance: null,
        workoutId: 'w1',
        at: '2026-01-01T00:00:00.000Z',
      );
      when(workouts.getRecordSets(userId: 'u1', exerciseId: null)).thenAnswer(
        (_) async => [
          (exerciseId: 'b', name: 'squat', category: Category.barbell, sets: [set(140, 3)]),
          (exerciseId: 'a', name: 'Bench', category: Category.barbell, sets: [set(100, 5)]),
          (exerciseId: 'c', name: 'Empty', category: Category.barbell, sets: [set(null, null)]),
        ],
      );

      final records = (await serve('/records', build('/me/records'))).toMap()['records'] as List;

      expect(records.map((r) => ((r as Map)['exercise'] as Map)['name']), ['Bench', 'squat']);
      expect(((records.first as Map)['heaviest'] as Map)['weight'], 100);
      expect((records.first as Map)['lastTrained'], '2026-01-01T00:00:00.000Z');
      expect(
        (await serve('/records', build('/me/records'))).toMap().containsKey('warnings'),
        isFalse,
        reason: 'nothing pending',
      );
    });
  });

  test('records name the pending anomalies on the exercises they fold', () async {
    Anomaly pending(String exerciseId) => Anomaly.fromJson({
      'id': '019def00-0000-7000-8000-00000000006${exerciseId == 'a' ? 1 : 2}',
      'workoutId': 'w1',
      'setId': '019def00-0000-7000-8000-000000000063',
      'exerciseId': exerciseId,
      'reason': 'outlier_weight',
      'observed': {'weight': 630, 'reps': 5},
      'status': 'pending',
      'detectedAt': '2026-01-02T00:00:00.000Z',
    });
    when(workouts.getRecordSets(userId: 'u1', exerciseId: null)).thenAnswer(
      (_) async => [
        (
          exerciseId: 'a',
          name: 'Bench',
          category: Category.barbell,
          sets: const [
            RecordSet(
              weight: 630,
              reps: 5,
              duration: null,
              distance: null,
              workoutId: 'w1',
              at: '2026-01-01T00:00:00Z',
            ),
          ],
        ),
      ],
    );
    when(anomalies.getPendingAnomalies(userId: 'u1')).thenAnswer((_) async => [pending('a'), pending('gone')]);

    final records = (await serve('/records', build('/me/records'))).toMap();

    expect((records['warnings'] as List).single, containsPair('exerciseId', 'a'));
  });

  group('goal progress', () {
    test('a workouts goal reads workouts only, in the user\'s week', () async {
      when(profiles.getProfile('u1')).thenAnswer(
        (_) async => User(
          id: 'u1',
          settings: const Settings(firstWeekday: DateTime.sunday),
        ),
      );
      when(goals.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1')).thenAnswer(
        (_) async => [
          Goal(
            id: 'g',
            metric: .workouts,
            cadence: .week,
            stages: [GoalStage(id: 's', target: 3)],
          ),
        ],
      );
      final now = DateTime.timestamp();
      when(workouts.getWorkoutSpans(userId: 'u1')).thenAnswer(
        (_) async => [(workoutId: 'w', start: now, duration: const Duration(hours: 1))],
      );

      final progress = (await getMyGoalProgress(build('/me/goals/progress'))).toMap();

      expect(progress['weekStart'], DateTime.sunday);
      final goal = (progress['goals'] as List).single as Map;
      expect([goal['current'], goal['progress']], [1, 0.33]);
      expect(DateTime.parse((goal['period'] as Map)['from'] as String).weekday, DateTime.sunday);
      verifyNever(workouts.getRecordSets(userId: anyNamed('userId')));
      verifyNever(exercises.getExercises(any));
    });
  });

  group('volume and balance', () {
    test('weeks start on the user\'s day, and the sets read are the window\'s', () async {
      when(profiles.getProfile('u1')).thenAnswer(
        (_) async => User(
          id: 'u1',
          settings: const Settings(firstWeekday: DateTime.sunday),
        ),
      );
      // a Wednesday: the default window is the four Sunday weeks ending with its
      final to = DateTime.utc(2026, 10, 14);
      when(
        workouts.getRecordSets(userId: 'u1', from: DateTime.utc(2026, 9, 20), to: to),
      ).thenAnswer((_) async => []);
      when(exercises.getExercises('u1')).thenAnswer((_) async => {'exercises': const []});
      when(workouts.getWorkoutSpans(userId: 'u1', from: DateTime.utc(2026, 9, 20), to: to)).thenAnswer(
        (_) async => [(workoutId: 'w', start: DateTime.utc(2026, 10, 12, 18), duration: const Duration(hours: 1))],
      );

      final volume = (await serve('/volume', build('/me/volume', query: {'to': '2026-10-14'}))).toMap();

      expect(volume['weekStart'], DateTime.sunday);
      expect((volume['weeks'] as List).map((week) => (week as Map)['week']), [
        '2026-09-20',
        '2026-09-27',
        '2026-10-04',
        '2026-10-11',
      ]);
      expect(volume['untrained'], hasLength(MuscleGroupKey.values.length));
      final last = (volume['weeks'] as List).last as Map;
      expect([last['workouts'], last['duration'], last['totalVolume']], [1, 3600, 0]);
    });

    test('a span over a year is a 400', () {
      expect(
        () => serve('/volume', build('/me/volume', query: {'from': '2025-01-01', 'to': '2026-06-01'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('balance reads the published pairs, Monday weeks when the user has no day', () async {
      final pairs = MockStorage();
      when(pairs.readPairs()).thenAnswer((_) async => null);
      when(profiles.getProfile('u1')).thenAnswer((_) async => User(id: 'u1'));
      when(
        workouts.getRecordSets(userId: 'u1', from: anyNamed('from'), to: anyNamed('to')),
      ).thenAnswer((_) async => []);
      when(exercises.getExercises('u1')).thenAnswer((_) async => {'exercises': const []});

      final balance = (await serve('/balance', build('/me/balance')..balancePairs = pairs)).toMap();

      expect(balance['weekStart'], DateTime.monday);
      expect(balance['weeks'], LensWindow.defaultWeeks);
      expect(balance['pairs'], isEmpty);
    });
  });

  group('exercise history', () {
    const exercise = '01900000-0000-7000-8000-000000000001';
    const older = '01900000-0000-7000-8000-0000000000a1';
    const newer = '01900000-0000-7000-8000-0000000000a2';

    RecordSet set(String workoutId, double weight, int reps) {
      return RecordSet(
        weight: weight,
        reps: reps,
        duration: null,
        distance: null,
        workoutId: workoutId,
        at: '2026-01-01T00:00:00.000Z',
      );
    }

    test('a malformed exercise id is a 404, a malformed cursor a 400', () {
      expect(
        () => serve('/exercises/:exerciseId/history', build('/me/exercises/x/history'), path: {'exerciseId': 'x'}),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => serve(
          '/exercises/:exerciseId/history',
          build('/me/exercises/$exercise/history', query: {'cursor': 'x'}),
          path: {'exerciseId': exercise},
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test("an exercise the user can't see is a 404", () {
      when(
        workouts.getExerciseHistory(userId: 'u1', exerciseId: exercise, cursor: null, limit: 20),
      ).thenAnswer((_) async => null);

      expect(
        () => serve(
          '/exercises/:exerciseId/history',
          build('/me/exercises/$exercise/history'),
          path: {'exerciseId': exercise},
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('sessions carry their sets and chart values, and the cursor is the last workout', () async {
      when(workouts.getExerciseHistory(userId: 'u1', exerciseId: exercise, cursor: newer, limit: 2)).thenAnswer(
        (_) async => (
          exerciseId: exercise,
          name: 'Bench',
          category: Category.barbell,
          sessions: Page<ExerciseSession>(
            items: [
              (workoutId: older, at: '2026-01-01T00:00:00.000Z', sets: [set(older, 100, 5), set(older, 110, 3)]),
            ],
            hasMore: true,
          ),
        ),
      );

      final page = (await serve(
        '/exercises/:exerciseId/history',
        build('/me/exercises/$exercise/history', query: {'cursor': newer, 'limit': '2'}),
        path: {'exerciseId': exercise},
      )).toMap();

      final session = (page['sessions'] as List).single as Map;
      expect(session['workoutId'], older);
      expect(session['sets'], [
        {'weight': 100, 'reps': 5},
        {'weight': 110, 'reps': 3},
      ]);
      expect((session['metrics'] as Map)['topSetWeight'], 110);
      expect((session['metrics'] as Map)['totalVolume'], 830);
      expect(page['cursor'], older);
      expect(page.containsKey('warnings'), isFalse);
    });

    test("warnings name the pending anomalies on this exercise's sessions shown", () async {
      Anomaly pending(String id, {required String workoutId, String? exerciseId}) => Anomaly.fromJson({
        'id': id,
        'workoutId': workoutId,
        'setId': ?(exerciseId == null ? null : '019def00-0000-7000-8000-000000000063'),
        'exerciseId': ?exerciseId,
        'reason': exerciseId == null ? 'duration_left_running' : 'outlier_weight',
        'observed': exerciseId == null ? {'seconds': 99999} : {'weight': 630, 'reps': 5},
        'status': 'pending',
        'detectedAt': '2026-01-02T00:00:00.000Z',
      });
      when(workouts.getExerciseHistory(userId: 'u1', exerciseId: exercise, cursor: null, limit: 20)).thenAnswer(
        (_) async => (
          exerciseId: exercise,
          name: 'Bench',
          category: Category.barbell,
          sessions: Page<ExerciseSession>(
            items: [
              (workoutId: older, at: '2026-01-01T00:00:00.000Z', sets: [set(older, 630, 5)]),
            ],
            hasMore: false,
          ),
        ),
      );
      when(anomalies.getPendingAnomalies(userId: 'u1')).thenAnswer(
        (_) async => [
          pending('019def00-0000-7000-8000-000000000061', workoutId: older, exerciseId: exercise),
          // another exercise in the same workout, the workout's own time, and a session not on this page
          pending('019def00-0000-7000-8000-000000000062', workoutId: older, exerciseId: 'other'),
          pending('019def00-0000-7000-8000-000000000064', workoutId: older),
          pending('019def00-0000-7000-8000-000000000065', workoutId: newer, exerciseId: exercise),
        ],
      );

      final page = (await serve(
        '/exercises/:exerciseId/history',
        build('/me/exercises/$exercise/history'),
        path: {'exerciseId': exercise},
      )).toMap();

      expect((page['warnings'] as List).single, containsPair('workoutId', older));
      expect((page['warnings'] as List).single, containsPair('exerciseId', exercise));
    });
  });

  group('library search', () {
    Map<String, Object?> exercise(String id, String name, {List<String> aliases = const [], bool archived = false}) {
      return {
        'id': id,
        'name': name,
        'category': 'Barbell',
        'target': 'Legs',
        'aliases': aliases,
        'own': false,
        'archived': archived,
      };
    }

    void library(List<Map<String, Object?>> rows, {String locale = 'en'}) {
      when(exercises.getExercises('u1', locale: locale)).thenAnswer(
        (_) async => {
          'exercises': rows,
          'glossary': {
            'bb': {
              'words': ['barbell'],
            },
          },
        },
      );
    }

    test('q is required, and a locale must be one served', () {
      expect(() => serve('/library', build('/me/library')), throwsA(isA<BadRequest>()));
      expect(() => serve('/library', build('/me/library', query: {'q': '  '})), throwsA(isA<BadRequest>()));
      expect(
        () => serve('/library', build('/me/library', query: {'q': 'squat', 'locale': 'de'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('ranks best match first, then by name, without archived exercises', () async {
      library([
        exercise('1', 'Romanian Deadlift', aliases: ['rdl']),
        exercise('2', 'Barbell Squat'),
        exercise('3', 'Squat'),
        exercise('4', 'Squat Jump', archived: true),
        exercise('5', 'Bench Press'),
        // a target this build doesn't know: left out, not a failed search
        {...exercise('6', 'Squat Curl'), 'target': 'Biceps'},
      ]);

      final squats =
          (await serve('/library', build('/me/library', query: {'q': 'squat'}))).toMap()['exercises'] as List;
      expect(squats.map((e) => (e as Map)['name']), ['Squat', 'Barbell Squat']);
      expect(squats.map((e) => (e as Map)['match']), ['prefix', 'words']);

      final rdl = (await serve('/library', build('/me/library', query: {'q': 'rdl'}))).toMap()['exercises'] as List;
      expect(rdl.single, containsPair('aliases', ['rdl']));
      expect(rdl.single, containsPair('match', 'vocabulary'));

      final glossary = (await serve('/library', build('/me/library', query: {'q': 'bb squat'}))).toMap()['exercises'];
      expect((glossary as List).map((e) => (e as Map)['name']), ['Barbell Squat']);
    });

    test('the locale parameter overrides the request language', () async {
      when(config.supportedLocales).thenReturn(['en', 'es']);
      library([exercise('3', 'Sentadilla')], locale: 'es');

      final found = (await serve('/library', build('/me/library', query: {'q': 'sentadila', 'locale': 'es'}))).toMap();
      expect(((found['exercises'] as List).single as Map)['match'], 'typo');
    });
  });
}
