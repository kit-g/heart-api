import 'exercise.dart';
import 'misc.dart';
import 'ts_for_id.dart';

abstract interface class Completes {
  bool get isCompleted;
}

/// A single set of an exercise
abstract interface class ExerciseSet with UsesTimestampForId implements Completes, Model, Storable {
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

  factory(
    Exercise exercise, {
    String? id,
    DateTime? start,
    int? reps,
    double? weight,
    double? distance,
    int? duration,
  }) {
    return switch (exercise) {
      Exercise e =>
        _ExerciseSet(
            id: id,
            exercise: e,
            start: start ?? DateTime.timestamp(),
          )
          ..reps = reps
          ..weight = weight
          ..distance = distance
          ..duration = duration,
    };
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

  ExerciseSet copy({DateTime? start});

  void setMeasurements({
    double? weight,
    int? reps,
    int? duration,
    double? distance,
  });
}

class _ExerciseSet with UsesTimestampForId implements ExerciseSet {
  final String? _id;
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
    required this.exercise,
    required this.start,
    this._id,
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
    };
  }

  @override
  String get id => _id ?? super.id;

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
        exercise: exercise,
        start: start ?? DateTime.timestamp(),
      )
      ..weight = weight
      ..duration = duration
      ..distance = distance
      ..reps = reps;
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
