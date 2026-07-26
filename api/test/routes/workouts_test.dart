import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
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
}
