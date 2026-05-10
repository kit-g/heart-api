import 'dart:math';

import 'exercise.dart';
import 'exercise_set.dart';
import 'misc.dart';
import 'uuid.dart';
import 'workout.dart';

abstract interface class Template
    with Iterable<WorkoutExercise>
    implements Comparable<Template>, HasExercises, Model, Storable {
  abstract String? name;

  bool get local;

  String get id;

  int get order;

  Workout toWorkout();

  factory Template.empty({required String id, required int order}) {
    return _Template(
      exercises: [],
      id: id,
      order: order,
      local: true,
    );
  }

  factory Template.fromJson(Map json) {
    return _Template(
      exercises: switch (json['exercises']) {
        List l => l.map((each) => WorkoutExercise.fromJson(each)).toList(),
        _ => [],
      },
      id: json['id'].toString(),
      order: json['order'],
      name: json['name'],
      local: false,
    );
  }

  factory Template.fromWorkout(String id, Workout workout, int order) {
    return _Template(
      exercises: workout.toList(),
      id: id,
      order: order,
      name: workout.name,
      local: true,
    );
  }

  factory Template.fromRow(Map<String, dynamic> row) {
    return _Template(
      id: row['id'].toString(),
      name: row['name'] as String? ?? '',
      order: (row['order_index'] as num?)?.toInt() ?? 0,
      exercises: switch (row['exercises']) {
        List l => l.map((each) => WorkoutExercise.fromJson(each as Map)).toList(),
        _ => [],
      },
      local: false,
      // sourceTemplateId: row['source_template_id']?.toString(),
      // assignedBy: switch (row['assigned_by_id']) {
      //   String id => Profile.fromJson({
      //     'username': row['assigned_by_username'],
      //     'avatar': row['assigned_by_avatar'],
      //   }),
      //   _ => null,
      // },
      // syncEnabled: row['sync_enabled'] as bool?,
    );
  }
}

class _Template with Iterable<WorkoutExercise>, HasUuid implements Template {
  @override
  final String id;
  @override
  String? name;
  @override
  int order;
  @override
  final bool local;

  final List<WorkoutExercise> _exercises;

  _Template({
    required List<WorkoutExercise> exercises,
    this.name,
    required this.id,
    required this.order,
    required this.local,
  }) : _exercises = exercises;

  @override
  Iterator<WorkoutExercise> get iterator => _exercises.iterator;

  @override
  WorkoutExercise add(Exercise exercise) {
    final ex = WorkoutExercise(starter: ExerciseSet(exercise));
    _exercises.add(ex);
    return ex;
  }

  @override
  bool remove(WorkoutExercise exercise) {
    return _exercises.remove(exercise);
  }

  @override
  bool operator ==(Object other) {
    return other is Template && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  int compareTo(Template other) {
    final orderComparison = order.compareTo(other.order);
    if (orderComparison != 0) {
      return orderComparison;
    }
    return id.compareTo(other.id);
  }

  // todo redo
  @override
  Workout toWorkout() {
    final exercises = <WorkoutExercise>[];
    for (final each in this) {
      if (each.isNotEmpty) {
        final exercise = WorkoutExercise(starter: each.first.copy());

        for (final (index, set) in each.skip(1).indexed) {
          final start = DateTime.timestamp().add(Duration(milliseconds: 2 * index));
          exercise.add(set.copy(start: start));
        }

        exercises.add(exercise);
      }
    }

    return Workout.fromExercises(exercises, name: name);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'order': order,
      'exercises': [
        for (final exercise in this) exercise.toMap(),
      ],
    };
  }

  @override
  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'name': name,
      'order_in_parent': order,
    };
  }

  @override
  void swap(WorkoutExercise toInsert, WorkoutExercise before) {
    final toInsertIndex = _exercises.indexOf(toInsert);
    final beforeIndex = _exercises.indexOf(before);
    final descending = beforeIndex > toInsertIndex;
    final newIndex = descending ? max(beforeIndex - 1, 0) : beforeIndex;

    _exercises
      ..remove(toInsert)
      ..insert(newIndex, toInsert);
  }

  @override
  void append(WorkoutExercise exercise) {
    _exercises
      ..remove(exercise)
      ..add(exercise);
  }
}

abstract interface class TemplateResponse implements Model, Iterable<Template> {
  List<Template> get templates;

  String? get cursor;

  factory TemplateResponse({
    required List<Template> templates,
    required String? cursor,
  }) = _TemplateResponse;
}

class _TemplateResponse with Iterable<Template> implements TemplateResponse {
  @override
  final List<Template> templates;
  @override
  final String? cursor;

  const _TemplateResponse({required this.templates, required this.cursor});

  @override
  Iterator<Template> get iterator => templates.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'templates': map((t) => t.toMap()).toList(),
      'cursor': ?cursor,
    };
  }
}
