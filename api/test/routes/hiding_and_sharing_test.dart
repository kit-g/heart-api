import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// The routes coaching's groundwork added: hiding a workout, what a student
/// shares, and a coach's read of a student's skips. The queries behind them are
/// covered against a database; this is the wiring and the statuses.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const workoutId = '01900000-0000-7000-8000-000000000001';

  group('hiding a workout', () {
    test('takes the time the device gives, and answers nothing', () async {
      when(
        app.db.hideWorkout(userId: anyNamed('userId'), workoutId: anyNamed('workoutId'), at: anyNamed('at')),
      ).thenAnswer((_) async {});

      final res = await app.send('PUT', '/workouts/$workoutId/hidden', body: {'at': '2026-07-01T10:00:00Z'});
      expect(res.status, 204);
      final at = verify(
        app.db.hideWorkout(userId: anyNamed('userId'), workoutId: workoutId, at: captureAnyNamed('at')),
      ).captured.single;
      expect(at, DateTime.utc(2026, 7, 1, 10));
    });

    test('a time that is no time is a 400', () async {
      final res = await app.send('PUT', '/workouts/$workoutId/hidden', body: {'at': 'soon'});
      expect(res.status, 400);
    });

    test('a workout the server hasn\'t got is a 404', () async {
      when(
        app.db.hideWorkout(userId: anyNamed('userId'), workoutId: anyNamed('workoutId'), at: anyNamed('at')),
      ).thenThrow(const NotFound(type: 'Workout', id: workoutId));
      expect((await app.send('PUT', '/workouts/$workoutId/hidden', body: {})).status, 404);
    });

    test('showing it again answers nothing', () async {
      when(
        app.db.unhideWorkout(userId: anyNamed('userId'), workoutId: anyNamed('workoutId')),
      ).thenAnswer((_) async {});
      expect((await app.send('DELETE', '/workouts/$workoutId/hidden')).status, 204);
    });

    test('the hidden ones come a page at a time', () async {
      when(
        app.db.getHiddenWorkouts(userId: anyNamed('userId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
      ).thenAnswer(
        (_) async => Page(
          items: [HiddenWorkout(id: workoutId, at: DateTime.utc(2026, 7))],
          hasMore: false,
        ),
      );
      final res = await app.send('GET', '/workouts/hidden');
      expect(res.status, 200);
      expect(res.body, contains(workoutId));
    });
  });

  test('what a student shares is the whole list', () async {
    when(
      app.db.changeConnectionShares(
        actorId: anyNamed('actorId'),
        targetId: anyNamed('targetId'),
        role: anyNamed('role'),
        domain: anyNamed('domain'),
        shares: anyNamed('shares'),
      ),
    ).thenAnswer(
      (_) async => Connection(
        targetId: 'coach-1',
        role: .student,
        domain: .fitness,
        status: .active,
        createdAt: DateTime.utc(2026),
        shares: const ['goals'],
      ),
    );

    final res = await app.send(
      'PUT',
      '/connections/coach-1|STUDENT|FITNESS/shares',
      body: {
        'shares': ['goals'],
      },
    );
    expect(res.status, 200);
    final shares = verify(
      app.db.changeConnectionShares(
        actorId: anyNamed('actorId'),
        targetId: 'coach-1',
        role: ConnectionRole.student,
        domain: ConnectionDomain.fitness,
        shares: captureAnyNamed('shares'),
      ),
    ).captured.single;
    expect(shares, {ConnectionShare.goals});

    expect(
      (await app.send('PUT', '/connections/coach-1|STUDENT|FITNESS/shares', body: {'shares': 'goals'})).status,
      400,
    );
  });

  test('a coach reads a student\'s skips a page at a time', () async {
    when(
      app.db.getTargetSkips(
        requesterId: anyNamed('requesterId'),
        targetUserId: anyNamed('targetUserId'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => const Page(items: [], hasMore: false));

    final res = await app.send('GET', '/accounts/student-1/skips');
    expect(res.status, 200);
    verify(
      app.db.getTargetSkips(
        requesterId: anyNamed('requesterId'),
        targetUserId: 'student-1',
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    );
  });
}
