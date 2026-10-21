import 'package:heart/core/openapi/shape.dart';
import 'package:heart_models/heart_models.dart';

import 'anomalies.dart';
import 'changes.dart';
import 'wire.dart';

/// `GET /me`: who a token acts as, and how much history there is to read.
class MeProfile implements Model {
  final User user;
  final AccountSummary summary;

  new({required this.user, required this.summary});

  static final Shape<MeProfile> shape = .object('MeProfile', {
    'id': .required(.string, (me) => me.user.id),
    'username': .optional(.string, (me) => me.user.displayName),
    'unitSystem': .optional(
      .enumOf<MeasurementUnit>(MeasurementUnit.values, (unit) => unit.name),
      (me) => me.user.settings.unitSystem,
    ),
    'counts': .required(_counts, (me) => me.summary),
  }, description: 'Who a token acts as, and how much history there is to read.');

  static final Shape<AccountSummary> _counts = .object('AccountCounts', {
    'workouts': .required(.integer, (summary) => summary[.workouts].count),
    'templates': .required(.integer, (summary) => summary[.templates].count),
    'templateFolders': .required(.integer, (summary) => summary[.templateFolders].count),
    'goals': .required(.integer, (summary) => summary[.goals].count),
    'customExercises': .required(.integer, (summary) => summary[.customExercises].count),
    'programs': .required(.integer, (summary) => summary[.programs].count),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
}

/// A workout as the `/me` surface publishes it: the app's wire shape, minus
/// what only the app's own plumbing needs. Images keep their id and URL and
/// lose their storage key and the back-reference to the workout they sit in.
///
/// Published shapes are additive only, so this is the one place that decides
/// what `/me` shows of a workout.
class MeWorkout implements Model {
  final Workout workout;

  new(this.workout);

  String get id => workout.id;

  static final Shape<MeWorkout> shape = .object(
    'MeWorkout',
    {
      'images': .required(.list(_image), (me) => me.workout.images?.values ?? const <WorkoutImage>[]),
    },
    base: (shape: workoutShape, read: (me) => me.workout),
  );

  static final Shape<WorkoutImage> _image = .object('MeWorkoutImage', {
    'id': .required(.string, (image) => image.id),
    'url': .optional(.string, (image) => image.link),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
}

/// `GET /me/workouts/changes`: one page of the change feed.
class MeWorkoutChanges implements Model {
  final WorkoutChanges changes;

  const new(this.changes);

  static final Shape<MeWorkoutChanges> shape = .object('MeWorkoutChanges', {
    'workouts': .required(.list(MeWorkout.shape), (me) => me.changes.upserted.map(MeWorkout.new)),
    'deleted': .required(.list(_deletion), (me) => me.changes.deleted),
    'cursor': .optional(.string, (me) => me.changes.cursor?.toString(), 'Where to resume: pass it back as `since`.'),
    'hasMore': .required(.boolean, (me) => me.changes.hasMore),
  });

  static final Shape<({String id, DateTime deletedAt})> _deletion = .object('MeDeletion', {
    'id': .required(.string, (deleted) => deleted.id),
    'deletedAt': .required(.dateTime, (deleted) => deleted.deletedAt.toUtc()),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
}

/// `GET /me/records`: personal records per exercise, as `toPersonalRecords`
/// computes them — the same records the app shows.
class MeRecords implements Model {
  final List<({ExerciseRecordSets exercise, Map<String, Object> records})> entries;
  final List<Anomaly> warnings;

  const new(this.entries, {this.warnings = const []});

  /// Folds each exercise's sets, leaving out exercises that never measured
  /// anything, ordered by name. [pending] are the anomalies nobody has looked
  /// at; those on the exercises folded come back as warnings.
  factory fold(List<ExerciseRecordSets> exercises, {List<Anomaly> pending = const []}) {
    final entries = [
      for (final exercise in exercises)
        if (exercise.sets.toPersonalRecords(exercise.category) case final records?)
          (exercise: exercise, records: records),
    ]..sort((a, b) => a.exercise.name.toLowerCase().compareTo(b.exercise.name.toLowerCase()));
    final folded = {for (final entry in entries) entry.exercise.exerciseId};
    return MeRecords(
      entries,
      warnings: [
        for (final anomaly in pending)
          if (folded.contains(anomaly.exerciseId)) anomaly,
      ],
    );
  }

  static final Shape<MeRecords> shape = .object('MeRecords', {
    'records': .required(.list(_entry), (me) => me.entries),
    'warnings': .optional(warningsShape, (me) => me.warnings.isEmpty ? null : me.warnings),
  });

  static final Shape<({ExerciseRecordSets exercise, Map<String, Object> records})> _entry = .object(
    'MeRecord',
    {
      'exercise': .required(_exercise, (entry) => entry.exercise),
      'lastTrained': .optional(.isoString, (entry) => entry.exercise.sets.lastOrNull?.at),
    },
    base: (
      shape: .unknown('each record kind toPersonalRecords computes (heaviest, oneRepMax, …), beside the exercise'),
      read: (entry) => entry.records,
    ),
  );

  static final Shape<ExerciseRecordSets> _exercise = .object('MeRecordExercise', {
    'id': .required(.string, (exercise) => exercise.exerciseId),
    'name': .required(.string, (exercise) => exercise.name),
    'category': .required(
      .enumOf<Category>(Category.values, (category) => category.value),
      (exercise) => exercise.category,
    ),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
}

/// One session in an exercise's history: its workout, when, the working sets
/// as they were done, and the values the progress chart plots for it
/// ([SessionMetrics.toSessionMetrics]).
class MeExerciseSession implements Model {
  final ExerciseSession session;
  final Category category;

  const new(this.session, this.category);

  String get workoutId => session.workoutId;

  static final Shape<MeExerciseSession> shape = .object('MeExerciseSession', {
    'workoutId': .required(.string, (me) => me.session.workoutId),
    'at': .required(.isoString, (me) => me.session.at),
    'sets': .required(.list(_set), (me) => me.session.sets),
    'metrics': .required(
      .mapOf(.number),
      (me) => me.session.sets.toSessionMetrics(me.category),
      'What the progress chart plots, by chart.',
    ),
  });

  static final Shape<RecordSet> _set = .object('MeSessionSet', {
    'weight': .optional(.number, (set) => set.weight),
    'reps': .optional(.integer, (set) => set.reps),
    'duration': .optional(.number, (set) => set.duration),
    'distance': .optional(.number, (set) => set.distance),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
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

  static final Shape<MeLibrarySearch> shape = .object('MeLibrarySearch', {
    'exercises': .required(.list(_result), (me) => me.results),
  });

  static final Shape<({Exercise exercise, SearchMatch match})> _result = .object('MeLibraryResult', {
    'id': .required(.string, (result) => result.exercise.id),
    'name': .required(.string, (result) => result.exercise.name),
    'category': .required(
      .enumOf<Category>(Category.values, (category) => category.value),
      (result) => result.exercise.category,
    ),
    'target': .required(.enumOf<Target>(Target.values, (target) => target.value), (result) => result.exercise.target),
    'aliases': .optional(.list(.string), (result) => result.exercise.aliases.isEmpty ? null : result.exercise.aliases),
    'own': .optional(.boolean, (result) => result.exercise.isMine ? true : null),
    'match': .required(.enumOf<SearchMatch>(SearchMatch.values, (match) => match.name), (result) => result.match),
  });

  @override
  Map<String, dynamic> toMap() => shape.encode(this) as Map<String, dynamic>;
}

/// A program as `/me` shows it: the program, where the user stands in it
/// (computed, never stored), and, for one program, each exercise's current
/// base, the next session planned from them, and the research behind a copy
/// of a library program.
abstract interface class MeProgram implements Model {
  Program get program;

  ProgramPosition get position;

  factory(
    Program program,
    ProgramPosition position, {
    Map<String, ProgramBase>? bases,
    Map<String, int>? stages,
    PlannedSession? nextSession,
    Map<String, dynamic>? research,
  }) = _MeProgram.new;
}

class _MeProgram implements MeProgram {
  @override
  final Program program;
  @override
  final ProgramPosition position;
  final Map<String, ProgramBase>? bases;
  final Map<String, int>? stages;
  final PlannedSession? nextSession;
  final Map<String, dynamic>? research;

  new(this.program, this.position, {this.bases, this.stages, this.nextSession, this.research});

  @override
  Map<String, dynamic> toMap() {
    return {
      ...program.toMap(),
      'position': position.toMap(),
      if (bases case final Map<String, ProgramBase> bases)
        'bases': {
          for (final MapEntry(:key, :value) in bases.entries)
            key: {
              'value': value.value,
              'at': value.at.toUtc().toIso8601String(),
              // keyed by the slot when it has one, which names no exercise
              'exerciseId': value.exerciseId,
              'slot': ?value.slot,
            },
        },
      // the stage each stages rule is on, keyed as bases are; absent is the first
      if (stages case final Map<String, int> stages when stages.isNotEmpty) 'stages': stages,
      'nextSession': ?nextSession?.toMap(),
      'research': ?research,
    };
  }
}

/// `GET /me/programs`.
class MePrograms implements Model {
  final Iterable<MeProgram> programs;

  const new(this.programs);

  @override
  Map<String, dynamic> toMap() => {
    'programs': [for (final program in programs) program.toMap()],
  };
}
