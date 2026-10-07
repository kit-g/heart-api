import 'package:heart_models/heart_models.dart';

import 'changes.dart';

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

/// `GET /me/workouts/changes`: one page of the change feed.
class MeWorkoutChanges implements Model {
  final WorkoutChanges changes;

  const new(this.changes);

  @override
  Map<String, dynamic> toMap() {
    return {
      'workouts': [for (final workout in changes.upserted) MeWorkout(workout).toMap()],
      'deleted': [
        for (final (:id, :deletedAt) in changes.deleted) {'id': id, 'deletedAt': deletedAt.toUtc().toIso8601String()},
      ],
      'cursor': ?changes.cursor?.toString(),
      'hasMore': changes.hasMore,
    };
  }
}

/// `GET /me/records`: personal records per exercise, as `toPersonalRecords`
/// computes them — the same records the app shows.
class MeRecords implements Model {
  final List<({ExerciseRecordSets exercise, Map<String, Object> records})> entries;

  const new(this.entries);

  /// Folds each exercise's sets, leaving out exercises that never measured
  /// anything, ordered by name.
  factory fold(List<ExerciseRecordSets> exercises) {
    final entries = [
      for (final exercise in exercises)
        if (exercise.sets.toPersonalRecords(exercise.category) case final records?)
          (exercise: exercise, records: records),
    ]..sort((a, b) => a.exercise.name.toLowerCase().compareTo(b.exercise.name.toLowerCase()));
    return MeRecords(entries);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'records': [
        for (final (:exercise, :records) in entries)
          {
            'exercise': {'id': exercise.exerciseId, 'name': exercise.name, 'category': exercise.category.value},
            ...records,
          },
      ],
    };
  }
}

/// One session in an exercise's history: its workout, when, the working sets
/// as they were done, and the values the progress chart plots for it
/// ([SessionMetrics.toSessionMetrics]).
class MeExerciseSession implements Model {
  final ExerciseSession session;
  final Category category;

  const new(this.session, this.category);

  String get workoutId => session.workoutId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'workoutId': session.workoutId,
      'at': session.at,
      'sets': [
        for (final set in session.sets)
          {'weight': ?set.weight, 'reps': ?set.reps, 'duration': ?set.duration, 'distance': ?set.distance},
      ],
      'metrics': session.sets.toSessionMetrics(category),
    };
  }
}

/// Library search results: the exercises [SearchMatch] ranks best first,
/// then by name, archived ones left out.
class MeLibrarySearch implements Model {
  final List<({Exercise exercise, SearchMatch match})> results;

  const new(this.results);

  /// Matches [query] against [exercises] with [glossary], the locale's
  /// search vocabulary, keeping the best [limit].
  factory rank(Iterable<Exercise> exercises, String query, {required SearchGlossary glossary, required int limit}) {
    final results =
        [
          for (final exercise in exercises)
            if (!exercise.isArchived)
              if (exercise.match(query, glossary: glossary) case final match?) (exercise: exercise, match: match),
        ]..sort(
          (a, b) => switch (a.match.compareTo(b.match)) {
            0 => a.exercise.name.toLowerCase().compareTo(b.exercise.name.toLowerCase()),
            final order => order,
          },
        );
    return MeLibrarySearch(results.take(limit).toList());
  }

  /// [rank] over the library as the exercise service returns it:
  /// `{exercises, glossary}`, already in one locale.
  factory fromLibrary(Map<String, dynamic> library, String query, {required int limit}) {
    return MeLibrarySearch.rank(
      // a row this build can't read (a custom exercise with a target the
      // enum doesn't know) is left out, not a failed search
      readEach(library['exercises'] as List? ?? const [], Exercise.fromJson),
      query,
      glossary: switch (library['glossary']) {
        final Map terms => SearchGlossary.fromJson(terms),
        _ => SearchGlossary.empty(),
      },
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'exercises': [
        for (final (:exercise, :match) in results)
          {
            'id': exercise.id,
            'name': exercise.name,
            'category': exercise.category.value,
            'target': exercise.target.value,
            if (exercise.aliases.isNotEmpty) 'aliases': [...exercise.aliases],
            if (exercise.isMine) 'own': true,
            'match': match.name,
          },
      ],
    };
  }
}
