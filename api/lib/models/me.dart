import 'package:heart_models/heart_models.dart';

/// `GET /me`: who a token acts as, and how much history there is to read.
abstract interface class MeProfile implements Model {
  factory({required User user, required AccountSummary summary}) = _MeProfile.new;
}

class _MeProfile implements MeProfile {
  final User user;
  final AccountSummary summary;

  new({required this.user, required this.summary});

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': user.id,
      'username': ?user.displayName,
      'unitSystem': ?user.settings.unitSystem?.name,
      'counts': {
        'workouts': summary[.workouts].count,
        'templates': summary[.templates].count,
        'templateFolders': summary[.templateFolders].count,
        'goals': summary[.goals].count,
        'customExercises': summary[.customExercises].count,
      },
    };
  }
}

/// A workout as the `/me` surface publishes it: the app's wire shape, minus
/// what only the app's own plumbing needs. Images keep their id and URL and
/// lose their storage key and the back-reference to the workout they sit in.
///
/// Published shapes are additive only, so this is the one place that decides
/// what `/me` shows of a workout.
abstract interface class MeWorkout implements Model {
  String get id;

  factory(Workout workout) = _MeWorkout.new;
}

class _MeWorkout implements MeWorkout {
  final Workout workout;

  new(this.workout);

  @override
  String get id => workout.id;

  @override
  Map<String, dynamic> toMap() {
    final map = workout.toMap();
    return {
      ...map,
      'images': [
        for (final image in workout.images?.values ?? const <WorkoutImage>[]) {'id': image.id, 'url': ?image.link},
      ],
    };
  }
}
