import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const workout = '01900000-0000-7000-8000-000000000001';

  test('logging through the real app has what it needs', () async {
    when(app.config.mediaDistribution).thenReturn('cdn.test');
    when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
        .thenAnswer((_) async => true);
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {});
    when(
      app.db.createWorkout(
        userId: anyNamed('userId'),
        body: anyNamed('body'),
        imageUrl: anyNamed('imageUrl'),
        loggedBy: 'u1',
      ),
    ).thenAnswer(
      (invocation) async => (
        Workout.fromRow({
          'id': workout,
          'name': 'In person',
          'started_at': DateTime.utc(2026),
          'exercises': const <Object?>[],
          'logged_by': 'u1',
        }, imageUrl: (key) => key),
        true,
      ),
    );

    final res = await app.send('POST', '/accounts/s/workouts', body: {'id': workout, 'name': 'In person'});
    expect(res.status, 201);
    final captured =
        verify(
              app.db.createWorkout(
                userId: captureAnyNamed('userId'),
                body: anyNamed('body'),
                imageUrl: anyNamed('imageUrl'),
                loggedBy: anyNamed('loggedBy'),
              ),
            ).captured.single
            as String;
    expect(captured, 's', reason: 'it is the student\'s');
  });

  test('someone who can\'t log for them is refused before anything is written', () async {
    when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
        .thenAnswer((_) async => false);
    final res = await app.send('POST', '/accounts/s/workouts', body: {'id': workout});
    expect(res.status, 403);
    verifyNever(
      app.db.createWorkout(
        userId: anyNamed('userId'),
        body: anyNamed('body'),
        imageUrl: anyNamed('imageUrl'),
        loggedBy: anyNamed('loggedBy'),
      ),
    );
  });
}
