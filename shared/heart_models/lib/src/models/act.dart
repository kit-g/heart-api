import 'exercise.dart';
import 'exercise_set.dart';
import 'utils.dart';

abstract interface class ExerciseAct with Iterable<ExerciseSet> implements Comparable<ExerciseAct> {
  String? get workoutName;

  String get workoutId;

  DateTime? get start;

  factory ExerciseAct.fromRows(Exercise exercise, List<Map<String, dynamic>> rows) {
    assert(rows.isNotEmpty, 'Cannot create ExerciseAct from empty rows');
    return _ExerciseAct._(
      workoutId: rows.first['workoutId'],
      workoutName: rows.first['workoutName'],
      start: switch (rows.first['exerciseId']) {
        String id => DateTime.tryParse(deSanitizeId(id)),
        _ => null,
      },
      sets: rows.map(
        (row) {
          return ExerciseSet.fromJson(exercise, row);
        },
      ),
    );
  }
}

class _ExerciseAct with Iterable<ExerciseSet> implements ExerciseAct {
  @override
  final String? workoutName;
  @override
  final String workoutId;
  @override
  final DateTime? start;

  final Iterable<ExerciseSet> _sets;

  const _ExerciseAct._({
    required Iterable<ExerciseSet> sets,
    required this.workoutId,
    this.workoutName,
    this.start,
  }) : _sets = sets;

  @override
  String toString() {
    return '$workoutName on $start, ${_sets.length} sets';
  }

  @override
  int compareTo(ExerciseAct other) {
    return switch ((start, other.start)) {
      (DateTime one, DateTime two) => two.compareTo(one),
      _ => 0,
    };
  }

  @override
  Iterator<ExerciseSet> get iterator => _sets.iterator;
}
