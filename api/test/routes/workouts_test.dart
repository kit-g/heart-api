import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/imports.dart';
import 'package:heart/routes/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _targetUserId = 'target-1';

Workout _fakeWorkout(String id) => Workout.fromRow(
  {
    'id': id,
    'name': 'Push',
    'started_at': DateTime.utc(2026, 1, 1),
    'completed_at': null,
    'exercises': const [],
    'images': null,
  },
  imageUrl: (k) => k,
);

void main() {
  late MockApiWorkoutService workouts;
  late MockAppConfig config;

  setUp(() {
    workouts = MockApiWorkoutService();
    config = MockAppConfig();
  });

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..config = config
    ..workoutsService = workouts;

  void stubGetWorkouts(Page<Workout> page) {
    when(
      workouts.getWorkouts(
        userId: anyNamed('userId'),
        targetUserId: anyNamed('targetUserId'),
        imageUrl: anyNamed('imageUrl'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => page);
  }

  Request getReq({Map<String, String> query = const {}}) => wire(
    bareRequest(method: Method.get, path: '/accounts/$_targetUserId/workouts', query: query),
  );

  group('getTargetUserWorkoutsFor', () {
    test('omits cursor when there is no next page', () async {
      stubGetWorkouts(Page(items: [_fakeWorkout('w-1')], hasMore: false));

      final result = await getTargetUserWorkoutsFor(getReq(), _targetUserId);

      expect(result.toMap()['workouts'], hasLength(1));
      expect(result.toMap().containsKey('cursor'), isFalse);
    });

    test('emits the last workout id as cursor when there is a next page', () async {
      stubGetWorkouts(Page(items: [_fakeWorkout('w-1'), _fakeWorkout('w-2')], hasMore: true));

      final result = await getTargetUserWorkoutsFor(getReq(), _targetUserId);

      expect(result.toMap()['cursor'], 'w-2');
    });

    test('clamps limit to the max and passes the cursor through', () async {
      stubGetWorkouts(const Page(items: [], hasMore: false));

      await getTargetUserWorkoutsFor(getReq(query: {'limit': '999', 'cursor': 'w-9'}), _targetUserId);

      verify(
        workouts.getWorkouts(
          userId: argThat(equals(_meId), named: 'userId'),
          targetUserId: argThat(equals(_targetUserId), named: 'targetUserId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: argThat(equals('w-9'), named: 'cursor'),
          limit: argThat(equals(100), named: 'limit'),
        ),
      ).called(1);
    });

    test('defaults to a limit of 30 with no cursor when unspecified', () async {
      stubGetWorkouts(const Page(items: [], hasMore: false));

      await getTargetUserWorkoutsFor(getReq(), _targetUserId);

      verify(
        workouts.getWorkouts(
          userId: argThat(equals(_meId), named: 'userId'),
          targetUserId: argThat(equals(_targetUserId), named: 'targetUserId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: argThat(isNull, named: 'cursor'),
          limit: argThat(equals(30), named: 'limit'),
        ),
      ).called(1);
    });

    test('propagates Forbidden from the service', () async {
      when(
        workouts.getWorkouts(
          userId: anyNamed('userId'),
          targetUserId: anyNamed('targetUserId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenThrow(const Forbidden(reason: 'nope'));

      await expectLater(
        getTargetUserWorkoutsFor(getReq(), _targetUserId),
        throwsA(isA<Forbidden>()),
      );
    });
  });

  group('patchWorkoutById', () {
    void stubPatch() {
      when(
        workouts.patchWorkout(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          name: anyNamed('name'),
          start: anyNamed('start'),
          end: anyNamed('end'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ).thenAnswer((_) async => _fakeWorkout('w-1'));
    }

    Request patchReq(Map<String, dynamic> body) =>
        wire(jsonRequest(method: Method.patch, path: '/workouts/w-1', body: body));

    test('passes the provided fields through to the service', () async {
      stubPatch();
      const startIso = '2026-07-20T18:00:00Z';
      const endIso = '2026-07-20T19:05:00Z';

      final out = await patchWorkoutById(
        patchReq({'name': 'Evening push', 'start': startIso, 'end': endIso}),
        'w-1',
      );

      expect(out.id, 'w-1');
      verify(
        workouts.patchWorkout(
          userId: argThat(equals(_meId), named: 'userId'),
          workoutId: argThat(equals('w-1'), named: 'workoutId'),
          name: argThat(equals('Evening push'), named: 'name'),
          start: argThat(equals(DateTime.parse(startIso)), named: 'start'),
          end: argThat(equals(DateTime.parse(endIso)), named: 'end'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ).called(1);
    });

    test('omitted fields arrive as null (left unchanged)', () async {
      stubPatch();

      await patchWorkoutById(patchReq({'start': '2026-07-20T18:00:00Z'}), 'w-1');

      verify(
        workouts.patchWorkout(
          userId: argThat(equals(_meId), named: 'userId'),
          workoutId: argThat(equals('w-1'), named: 'workoutId'),
          name: argThat(isNull, named: 'name'),
          start: argThat(equals(DateTime.parse('2026-07-20T18:00:00Z')), named: 'start'),
          end: argThat(isNull, named: 'end'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ).called(1);
    });

    test('rejects an empty body (no fields to change)', () async {
      await expectLater(patchWorkoutById(patchReq({}), 'w-1'), throwsA(isA<BadRequest>()));
      verifyNever(
        workouts.patchWorkout(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          name: anyNamed('name'),
          start: anyNamed('start'),
          end: anyNamed('end'),
          imageUrl: anyNamed('imageUrl'),
        ),
      );
    });

    test('rejects end before start', () async {
      await expectLater(
        patchWorkoutById(
          patchReq({'start': '2026-07-20T19:00:00Z', 'end': '2026-07-20T18:00:00Z'}),
          'w-1',
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a blank name', () async {
      await expectLater(patchWorkoutById(patchReq({'name': ''}), 'w-1'), throwsA(isA<BadRequest>()));
    });

    test('propagates NotFound for a workout the user does not own', () async {
      when(
        workouts.patchWorkout(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          name: anyNamed('name'),
          start: anyNamed('start'),
          end: anyNamed('end'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ).thenThrow(const NotFound(type: 'Workout', id: 'w-1'));

      await expectLater(
        patchWorkoutById(patchReq({'name': 'x'}), 'w-1'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('importWorkouts', () {
    const csv =
        'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds\n'
        '2023-01-15 17:35:12,Push Day,1h,Bench Press (Barbell),1,80,5,0,0\n';

    const report = WorkoutImportReport(
      source: 'strong',
      workoutsFound: 1,
      workoutsCreated: 1,
      setsCreated: 1,
      setsSkipped: 0,
      exercisesMatched: 1,
      exercisesCreated: [],
      exercisesSkipped: [],
      rowsSkipped: 0,
      workoutsDropped: 0,
      setsDropped: 0,
    );

    Request importReq({String body = csv, Map<String, String> query = const {'source': 'strong'}}) =>
        wire(textRequest(path: '/workouts/imports', body: body, query: query));

    test('parses the CSV and hands the batch to the service under the caller id', () async {
      when(
        workouts.importWorkouts(
          userId: anyNamed('userId'),
          batch: anyNamed('batch'),
          createCustom: anyNamed('createCustom'),
        ),
      ).thenAnswer((_) async => report);

      final result = await importWorkouts(importReq());

      expect(result.toMap()['workoutsCreated'], 1);
      final captured = verify(
        workouts.importWorkouts(
          userId: _meId,
          batch: captureAnyNamed('batch'),
          createCustom: captureAnyNamed('createCustom'),
        ),
      ).captured;
      final batch = captured.first as WorkoutImport;
      expect(batch.source, 'strong');
      expect(batch.workouts.single.name, 'Push Day');
      // a raw CSV body carries no consent decision: create all
      expect(captured.last, isNull);
    });

    test('a JSON envelope carries the consent decision alongside the CSV', () async {
      when(
        workouts.importWorkouts(
          userId: anyNamed('userId'),
          batch: anyNamed('batch'),
          createCustom: anyNamed('createCustom'),
        ),
      ).thenAnswer((_) async => report);

      final req = wire(
        jsonRequest(
          path: '/workouts/imports',
          query: const {'source': 'strong'},
          body: {
            'csv': csv,
            'createCustom': ['Free motion Row'],
          },
        ),
      );
      await importWorkouts(req);

      final captured = verify(
        workouts.importWorkouts(
          userId: _meId,
          batch: captureAnyNamed('batch'),
          createCustom: captureAnyNamed('createCustom'),
        ),
      ).captured;
      expect((captured.first as WorkoutImport).workouts.single.name, 'Push Day');
      expect(captured.last, ['Free motion Row']);
    });

    test('rejects an envelope whose createCustom is not a list of strings', () async {
      final req = wire(
        jsonRequest(
          path: '/workouts/imports',
          query: const {'source': 'strong'},
          body: {'csv': csv, 'createCustom': 'Free motion Row'},
        ),
      );
      await expectLater(importWorkouts(req), throwsA(isA<BadRequest>()));
    });

    test('dryRun=true previews instead of importing', () async {
      const preview = WorkoutImportPreview(
        source: 'strong',
        workoutsFound: 1,
        workoutsAlreadyImported: 0,
        setsFound: 1,
        exercisesMatched: 1,
        exercisesUnmatched: [],
        rowsSkipped: 0,
        workoutsDropped: 0,
        setsDropped: 0,
      );
      when(
        workouts.previewImport(userId: anyNamed('userId'), batch: anyNamed('batch')),
      ).thenAnswer((_) async => preview);

      final result = await importWorkouts(importReq(query: {'source': 'strong', 'dryRun': 'true'}));

      expect(result.toMap()['workoutsFound'], 1);
      verify(workouts.previewImport(userId: _meId, batch: anyNamed('batch')));
      verifyNever(
        workouts.importWorkouts(
          userId: anyNamed('userId'),
          batch: anyNamed('batch'),
          createCustom: anyNamed('createCustom'),
        ),
      );
    });

    test('a large import triggers the monitoring alert without ever failing the request', () async {
      // 600 workouts created crosses the alert threshold; the test request
      // carries no AWS context, so the publish attempt itself throws — the
      // handler must swallow that and still return the report
      const large = WorkoutImportReport(
        source: 'strong',
        workoutsFound: 600,
        workoutsCreated: 600,
        setsCreated: 600,
        setsSkipped: 0,
        exercisesMatched: 1,
        exercisesCreated: [],
        exercisesSkipped: [],
        rowsSkipped: 0,
        workoutsDropped: 0,
        setsDropped: 0,
      );
      when(
        workouts.importWorkouts(
          userId: anyNamed('userId'),
          batch: anyNamed('batch'),
          createCustom: anyNamed('createCustom'),
        ),
      ).thenAnswer((_) async => large);

      final result = await importWorkouts(importReq());
      expect(result.toMap()['workoutsCreated'], 600);
    });

    test('rejects a malformed dryRun', () async {
      await expectLater(
        importWorkouts(importReq(query: {'source': 'strong', 'dryRun': 'yes'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a missing source', () async {
      await expectLater(importWorkouts(importReq(query: {})), throwsA(isA<BadRequest>()));
    });

    test('rejects an unsupported source', () async {
      await expectLater(
        importWorkouts(importReq(query: {'source': 'hevy'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a body that is not a Strong export', () async {
      await expectLater(importWorkouts(importReq(body: 'a,b\n1,2\n')), throwsA(isA<BadRequest>()));
    });

    test('rejects a malformed tzOffset', () async {
      await expectLater(
        importWorkouts(importReq(query: {'source': 'strong', 'tzOffset': 'PST'})),
        throwsA(isA<BadRequest>()),
      );
    });
  });
}
