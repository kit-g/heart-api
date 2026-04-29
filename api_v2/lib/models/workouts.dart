import 'dart:convert';
import 'dart:typed_data';

import 'package:heart_models/heart_models.dart';

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


abstract interface class ApiWorkoutService {
  Future<WorkoutResponse> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize,
  });

  Future<Workout> getWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
  });

  Future<Workout> createWorkout({
    required String userId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  Future<Workout> updateWorkout({
    required String userId,
    required String workoutId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  Future<void> deleteWorkout({
    required String userId,
    required String workoutId,
  });
}

class WorkoutRequest {
  final String userId;
  final Map<String, dynamic> body;

  const WorkoutRequest({
    required this.userId,
    required this.body,
  });

  DateTime? _dt(dynamic value) => switch (value) {
    String s => DateTime.tryParse(s),
    DateTime dt => dt,
    _ => null,
  };

  List<Map> _exercises() {
    return ((body['exercises'] as List? ?? []).cast<Map>())
        .map(
          (ex) {
            final name = switch (ex['exercise']) {
              String s => s,
              {'name': String n} => n,
              _ => null,
            };
            return {'exercise_name': name, 'order': ex['order'], 'sets': ex['sets'] ?? []};
          },
        )
        .where((e) => e['exercise_name'] != null)
        .toList();
  }

  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': body['name'],
      'startedAt': _dt(body['start']),
      'completedAt': _dt(body['end']),
      'exercises': jsonEncode(_exercises()),
    };
  }
}
