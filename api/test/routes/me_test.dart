import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
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
}
