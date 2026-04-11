import 'dart:typed_data';

import 'package:heart_models/heart_models.dart';

abstract interface class SetItem implements Model {
  double? get weight;

  int? get reps;

  int? get duration;

  double? get distance;

  String get id;

  bool get completed;

  factory SetItem.fromRow(Map<String, dynamic> row) {
    return _SetItem(
      weight: (row['weight'] as num?)?.toDouble(),
      distance: (row['distance'] as num?)?.toDouble(),
      reps: (row['reps'] as num?)?.toInt(),
      duration: (row['duration'] as num?)?.toInt(),
      id: row['id'] as String,
      completed: row['completed'] as bool,
    );
  }
}

class _SetItem implements SetItem {
  @override
  final double? weight;
  @override
  final int? reps;
  @override
  final int? duration;
  @override
  final double? distance;
  @override
  final String id;
  @override
  final bool completed;

  const _SetItem({
    this.weight,
    this.duration,
    this.distance,
    this.reps,
    required this.id,
    required this.completed,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'weight': ?weight,
      'reps': ?reps,
      'id': id,
      'completed': completed,
      'distance': ?distance,
      'duration': ?duration,
    };
  }
}

abstract interface class ExerciseItem implements Iterable<SetItem>, Model {
  String get id;

  String get exerciseId;

  int get exerciseOrder;

  List<SetItem> get sets;

  factory ExerciseItem.fromRow(Map row) {
    return _ExerciseItem(
      id: row['id'] as String,
      exerciseId: row['exercise_id'] as String,
      exerciseOrder: (row['exercise_order'] as num).toInt(),
      sets: (row['sets'] as List).map((e) => SetItem.fromRow(e as Map<String, dynamic>)).toList(),
    );
  }
}

class _ExerciseItem with Iterable<SetItem> implements ExerciseItem {
  @override
  final String id;
  @override
  final String exerciseId;
  @override
  final int exerciseOrder;
  @override
  final List<SetItem> sets;

  const _ExerciseItem({
    required this.id,
    required this.exerciseId,
    required this.exerciseOrder,
    required this.sets,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'exercise': exerciseId,
      'order': exerciseOrder,
      'sets': sets.map((e) => e.toMap()).toList(),
    };
  }

  @override
  Iterator<SetItem> get iterator => sets.iterator;
}

abstract interface class WorkoutImageItem implements Model, WorkoutImage {
  factory WorkoutImageItem(final String key, {required String Function(String) url, required String workoutId}) {
    return _WorkoutImageItem(
      key: key,
      link: url(key),
      workoutId: workoutId,
      id: key.split('/').last.split('.').first,
    );
  }
}

class _WorkoutImageItem implements WorkoutImageItem {
  @override
  final String key;
  @override
  final String id;
  @override
  final String workoutId;
  @override
  final String link;

  const _WorkoutImageItem({
    required this.key,
    required this.link,
    required this.id,
    required this.workoutId,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'url': link,
      'id': id,
      'workoutId': workoutId,
    };
  }

  @override
  Uint8List? get bytes => null;

  @override
  int compareTo(WorkoutImage other) {
    throw UnimplementedError();
  }

  @override
  DateTime? get timestamp => throw UnimplementedError();

  @override
  Map<String, dynamic> toRow() {
    throw UnimplementedError();
  }
}

abstract interface class WorkoutItem implements Iterable<ExerciseItem>, Model {
  String get pk;

  String get sk;

  String get id;

  String get name;

  DateTime get start;

  DateTime? get end;

  List<ExerciseItem> get exercises;

  List<WorkoutImageItem>? get images;

  factory WorkoutItem.fromRow(Map<String, dynamic> row, {required String Function(String) imageUrl}) {
    final sk = row['SK'] as String;
    final id = sk.split('#').last;
    return _WorkoutItem(
      pk: row['PK'] as String,
      sk: sk,
      id: id,
      name: row['name'] as String,
      start: DateTime.parse(row['start'] as String),
      end: row['end'] != null ? DateTime.parse(row['end'] as String) : null,
      exercises: switch (row['exercises']) {
        List l => l.map((e) => ExerciseItem.fromRow(e)).toList(),
        _ => [],
      },
      images: switch (row['images']) {
        Iterable l => l.map((key) => WorkoutImageItem(key, url: imageUrl, workoutId: id)).toList(),
        _ => null,
      },
    );
  }
}

class _WorkoutItem with Iterable<ExerciseItem> implements WorkoutItem {
  @override
  final String pk;
  @override
  final String sk;
  @override
  final String id;
  @override
  final String name;
  @override
  final DateTime start;
  @override
  final DateTime? end;
  @override
  final List<ExerciseItem> exercises;
  @override
  final List<WorkoutImageItem>? images;

  const _WorkoutItem({
    required this.pk,
    required this.sk,
    required this.id,
    required this.name,
    required this.start,
    this.end,
    required this.exercises,
    this.images,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'id': id,
      'start': start.toIso8601String(),
      'end': ?end?.toIso8601String(),
      'exercises': exercises.map((e) => e.toMap()).toList(),
      'images': ?images?.map((e) => e.toMap()).toList(),
    };
  }

  @override
  Iterator<ExerciseItem> get iterator => exercises.iterator;
}

abstract interface class WorkoutListResponse implements Model, Iterable<WorkoutItem> {
  List<WorkoutItem> get workouts;

  String? get cursor;

  factory WorkoutListResponse({
    required final List<WorkoutItem> workouts,
    required final String? cursor,
  }) = _WorkoutListResponse;
}

class _WorkoutListResponse with Iterable<WorkoutItem> implements WorkoutListResponse {
  @override
  final List<WorkoutItem> workouts;
  @override
  final String? cursor;

  const _WorkoutListResponse({
    required this.workouts,
    required this.cursor,
  });

  @override
  Iterator<WorkoutItem> get iterator => workouts.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'workouts': map((w) => w.toMap()).toList(),
      'cursor': cursor,
    };
  }
}

abstract interface class ApiWorkoutService {
  Future<WorkoutListResponse> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize,
  });
}
