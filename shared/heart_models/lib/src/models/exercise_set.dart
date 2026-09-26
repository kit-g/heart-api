import 'exercise.dart';
import 'misc.dart';
import 'uuid.dart';

abstract interface class Completes {
  bool get isCompleted;
}

/// What kind of set this was. Warm-ups are left out of an exercise's records
/// and volume ([WorkoutExercise.best], [WorkoutExercise.total]); drop and
/// failure sets count like any other. Failure and an RPE of 10 are
/// independent: neither implies the other.
enum SetType {
  normal('normal'),
  warmup('warmup'),
  drop('drop'),
  failure('failure');

  /// The wire word, `set_type` on a set.
  final String value;

  new(this.value);

  /// Absent or null is [normal], the type of every set recorded before types
  /// existed; an unknown word is an error.
  factory fromString(String? v) {
    return switch (v) {
      null => normal,
      'normal' => normal,
      'warmup' => warmup,
      'drop' => drop,
      'failure' => failure,
      _ => throw ArgumentError.value(v, 'set_type', 'unknown set type'),
    };
  }

  /// [fromString] for reading stored data: a word this build doesn't know (a
  /// type added after it shipped) reads as [normal] rather than failing the
  /// whole read.
  factory lenient(String? v) {
    return values.firstWhere((type) => type.value == v, orElse: () => normal);
  }
}

/// A single set of an exercise
abstract interface class ExerciseSet implements Completes, Model, Storable, Comparable<ExerciseSet> {
  /// Client-minted v7 uuid. Firebase-era sets used the [start] timestamp as
  /// their id (and copies staggered starts by a few milliseconds to keep ids
  /// unique); those ids survive in old rows as opaque strings, but identity is
  /// no longer derived from time.
  String get id;

  DateTime get start;

  Exercise get exercise;

  double? get weight;

  int? get reps;

  int? get duration;

  double? get distance;

  @override
  abstract bool isCompleted;

  /// When the set was ticked complete. Together with [start] this bounds the
  /// set's work window, letting clients separate work time from rest time.
  abstract DateTime? completedAt;

  abstract SetType setType;

  /// Rate of perceived exertion as the lifter rated it: 1–10 in whole or half
  /// points, null when not rated. Stored as RPE whatever the user reads it as;
  /// reps in reserve is `10 - rpe`, a display choice. Valid on a set of any
  /// category.
  abstract double? rpe;

  factory(
    Exercise exercise, {
    String? id,
    DateTime? start,
    int? reps,
    double? weight,
    double? distance,
    int? duration,
    SetType setType = .normal,
    double? rpe,
  }) {
    final set =
        _ExerciseSet(
            id: id ?? uuidV7(),
            exercise: exercise,
            start: start ?? DateTime.timestamp(),
          )
          ..setType = setType
          ..rpe = rpe;
    // Only the measurements that exist for the exercise's category are kept,
    // mirroring [setMeasurements]. Legacy serializers wrote zero-valued
    // defaults into every field; dropping the inapplicable ones at
    // construction is what lets that junk heal as sets round-trip through
    // [fromJson]/[toMap].
    switch (exercise.category) {
      case .weightedBodyWeight:
      case .assistedBodyWeight:
      case .machine:
      case .barbell:
      case .dumbbell:
        set
          ..weight = weight
          ..reps = reps;
      case .repsOnly:
        set.reps = reps;
      case .cardio:
        set
          ..distance = distance
          ..duration = duration;
      case .duration:
        set.duration = duration;
    }
    return set;
  }

  factory fromJson(Exercise exercise, Map json) {
    return ExerciseSet(
        exercise,
        reps: json['reps'],
        id: json['id'],
        weight: switch (json['weight']) {
          num weight => weight.toDouble(),
          _ => null,
        },
        duration: (json['duration'] as num?)?.toInt(),
        distance: (json['distance'] as num?)?.toDouble(),
        start: switch (json['started_at']) {
          String s => DateTime.parse(s),
          DateTime dt => dt,
          _ => DateTime.timestamp(),
        },
        setType: SetType.lenient(json['set_type'] as String?),
        rpe: (json['rpe'] as num?)?.toDouble(),
      )
      ..isCompleted = switch (json['completed']) {
        bool completed => completed,
        1 => true,
        _ => false,
      }
      ..completedAt = switch (json['completed_at']) {
        String s => DateTime.tryParse(s),
        DateTime dt => dt,
        _ => null,
      };
  }

  bool get canBeCompleted;

  double? get total;

  Category get category;

  bool operator >(covariant ExerciseSet other);

  bool operator >=(covariant ExerciseSet other);

  bool operator <(covariant ExerciseSet other);

  bool operator <=(covariant ExerciseSet other);

  /// A fresh set with the same measurements and type, for repeating a session
  /// or starting one from a template. The [rpe] is a rating of the original
  /// effort, so the copy starts unrated.
  ExerciseSet copy({DateTime? start});

  Duration elapsed();

  void setMeasurements({
    double? weight,
    int? reps,
    int? duration,
    double? distance,
  });
}

class _ExerciseSet implements ExerciseSet {
  @override
  final String id;
  @override
  final Exercise exercise;
  @override
  final DateTime start;
  @override
  double? weight;
  @override
  int? reps;
  @override
  int? duration;
  @override
  double? distance;

  new({
    required this.id,
    required this.exercise,
    required this.start,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'completed': isCompleted,
      'started_at': start.toIso8601String(),
      'completed_at': ?completedAt?.toIso8601String(),
      'reps': ?reps,
      'duration': ?duration,
      'distance': ?distance,
      'weight': ?weight,
      // always present, so a client that knows the fields can clear them; a
      // body without the keys leaves the stored values alone
      'set_type': setType.value,
      'rpe': rpe,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ExerciseSet && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  int compareTo(covariant ExerciseSet other) {
    return start.compareTo(other.start);
  }

  @override
  Duration elapsed() => DateTime.now().difference(start);

  @override
  bool operator >(covariant ExerciseSet other) {
    return (total ?? 0) > (other.total ?? 0);
  }

  @override
  bool operator >=(covariant ExerciseSet other) {
    return (total ?? 0) >= (other.total ?? 0);
  }

  @override
  bool operator <(covariant ExerciseSet other) {
    return (total ?? 0) < (other.total ?? 0);
  }

  @override
  bool operator <=(covariant ExerciseSet other) {
    return (total ?? 0) <= (other.total ?? 0);
  }

  @override
  bool isCompleted = false;

  @override
  DateTime? completedAt;

  @override
  SetType setType = .normal;

  @override
  double? rpe;

  @override
  bool get canBeCompleted {
    switch (category) {
      case .assistedBodyWeight:
      case .barbell:
      case .dumbbell:
      case .machine:
        return reps != null && weight != null;
      case .weightedBodyWeight:
      case .repsOnly:
        return reps != null;
      case .cardio:
        return duration != null && distance != null;
      case .duration:
        return duration != null;
    }
  }

  @override
  Category get category => exercise.category;

  @override
  ExerciseSet copy({DateTime? start}) {
    return _ExerciseSet(
        id: uuidV7(),
        exercise: exercise,
        start: start ?? DateTime.timestamp(),
      )
      ..weight = weight
      ..duration = duration
      ..distance = distance
      ..reps = reps
      ..setType = setType;
  }

  @override
  void setMeasurements({double? weight, int? reps, int? duration, double? distance}) {
    switch (category) {
      case .weightedBodyWeight:
      case .assistedBodyWeight:
      case .machine:
      case .barbell:
      case .dumbbell:
        this
          ..weight = weight ?? this.weight
          ..reps = reps ?? this.reps;
      case .repsOnly:
        this.reps = reps ?? this.reps;
      case .cardio:
        this
          ..distance = distance ?? this.distance
          ..duration = duration ?? this.duration;
      case .duration:
        this.duration = duration ?? this.duration;
    }
  }

  @override
  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'reps': ?reps,
      'weight': ?weight,
      'duration': ?duration,
      'distance': ?distance,
      'completed': isCompleted ? 1 : 0,
    };
  }

  @override
  double? get total {
    switch (category) {
      case .weightedBodyWeight:
      case .assistedBodyWeight:
      case .barbell:
      case .dumbbell:
      case .machine:
        return switch ((weight, reps)) {
          (double w, int r) => w * r,
          _ => null,
        };
      case .repsOnly:
        return reps?.toDouble();
      case .cardio:
        return switch ((duration, distance)) {
          (int duration, int distance) => duration * distance.toDouble(),
          _ => null,
        };
      case .duration:
        return duration?.toDouble();
    }
  }

  @override
  String toString() {
    return '$exercise $id';
  }
}
