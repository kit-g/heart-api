import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/me.dart';
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
  late MockAppConfig config;

  setUp(() {
    profiles = MockApiProfileService();
    workouts = MockApiWorkoutService();
    exercises = MockExerciseService();
    goals = MockIdempotentGoalService();
    config = MockAppConfig();
    when(config.supportedLocales).thenReturn(['en']);
    when(config.defaultLocale).thenReturn('en');
  });

  Request build(String path, {Map<String, String> query = const {}}) {
    return bareRequest(method: Method.get, path: path, query: query)
      ..user = User(id: 'u1')
      ..config = config
      ..profileService = profiles
      ..workoutsService = workouts
      ..exerciseService = exercises
      ..goalService = goals;
  }

  test('getMe is a 404 when the account has no profile', () {
    when(profiles.getProfile('u1')).thenAnswer((_) async => null);
    expect(() => getMe(build('/me')), throwsA(isA<NotFound>()));
  });

  test('getMyWorkoutById rejects a malformed id without a query', () {
    expect(() => getMyWorkoutById(build('/me/workouts/x'), 'x'), throwsA(isA<NotFound>()));
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

    await getMyGoals(build('/me/goals'));

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

      final result = await exportMe(exportRequest());

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

      final result = await exportMe(exportRequest(), inlineLimit: 10);

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
        () => exportMe(exportRequest()),
        throwsA(
          isA<TooManyRequests>()
              .having((e) => e.code, 'code', 'export_limit')
              .having((e) => e.retryAfter, 'retryAfter', inInclusiveRange(3500, 3600)),
        ),
      );
    });

    test('the format is required and must be known, before the allowance is spent', () {
      expect(() => exportMe(exportRequest(const {})), throwsA(isA<BadRequest>()));
      expect(() => exportMe(exportRequest(const {'format': 'hevy'})), throwsA(isA<BadRequest>()));
      verifyNever(tokens.claimExport(any));
    });
  });

  group('changes and records', () {
    test('a since that is not a cursor from the feed is a 400', () {
      expect(
        () => getMyWorkoutChanges(build('/me/workouts/changes', query: {'since': 'garbage'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('a malformed exerciseId is a 400', () {
      expect(() => getMyRecords(build('/me/records', query: {'exerciseId': 'x'})), throwsA(isA<BadRequest>()));
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

      final records = (await getMyRecords(build('/me/records'))).toMap()['records'] as List;

      expect(records.map((r) => ((r as Map)['exercise'] as Map)['name']), ['Bench', 'squat']);
      expect(((records.first as Map)['heaviest'] as Map)['weight'], 100);
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
        () => getMyExerciseHistoryById(build('/me/exercises/x/history'), 'x'),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => getMyExerciseHistoryById(build('/me/exercises/$exercise/history', query: {'cursor': 'x'}), exercise),
        throwsA(isA<BadRequest>()),
      );
    });

    test("an exercise the user can't see is a 404", () {
      when(
        workouts.getExerciseHistory(userId: 'u1', exerciseId: exercise, cursor: null, limit: 20),
      ).thenAnswer((_) async => null);

      expect(
        () => getMyExerciseHistoryById(build('/me/exercises/$exercise/history'), exercise),
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

      final page = (await getMyExerciseHistoryById(
        build('/me/exercises/$exercise/history', query: {'cursor': newer, 'limit': '2'}),
        exercise,
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
    });
  });
}
