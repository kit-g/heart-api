import 'misc.dart';

enum CommentTarget {
  workout('workout', 'workout_id'),
  workoutExercise('workout_exercise', 'workout_exercise_id'),
  exerciseSet('exercise_set', 'exercise_set_id'),
  workoutImage('workout_image', 'workout_image_id'),
  ;

  final String value;
  final String column;

  const new(this.value, this.column);

  factory fromString(String v) {
    return switch (v) {
      'workout' => workout,
      'workout_exercise' => workoutExercise,
      'exercise_set' => exerciseSet,
      'workout_image' => workoutImage,
      _ => throw ArgumentError('unknown comment target: $v'),
    };
  }
}

abstract interface class Comment implements Model {
  String get id;

  String get authorId;

  String get body;

  CommentTarget get targetType;

  String get targetId;

  DateTime get createdAt;

  DateTime? get editedAt;

  factory({
    required String id,
    required String authorId,
    required String body,
    required CommentTarget targetType,
    required String targetId,
    required DateTime createdAt,
    DateTime? editedAt,
  }) = _Comment.new;

  factory fromRow(Map<String, dynamic> row) {
    return Comment(
      id: row['id'].toString(),
      authorId: row['author_id'] as String,
      body: row['body'] as String,
      targetType: CommentTarget.fromString(row['target_type'] as String),
      targetId: row['target_id'].toString(),
      createdAt: switch (row['created_at']) {
        DateTime dt => dt,
        String s => DateTime.parse(s),
        _ => DateTime.now(),
      },
      editedAt: switch (row['edited_at']) {
        DateTime dt => dt,
        String s => DateTime.parse(s),
        _ => null,
      },
    );
  }
}

class const _Comment({
  required this.id,
  required this.authorId,
  required this.body,
  required this.targetType,
  required this.targetId,
  required this.createdAt,
  this.editedAt,
}) implements Comment {
  @override
  final String id;
  @override
  final String authorId;
  @override
  final String body;
  @override
  final CommentTarget targetType;
  @override
  final String targetId;
  @override
  final DateTime createdAt;
  @override
  final DateTime? editedAt;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorId': authorId,
      'body': body,
      'targetType': targetType.value,
      'targetId': targetId,
      'createdAt': createdAt.toIso8601String(),
      'editedAt': ?editedAt?.toIso8601String(),
    };
  }
}
