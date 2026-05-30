import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('CommentTarget.fromString', () {
    for (final (raw, expected) in [
      ('workout', CommentTarget.workout),
      ('workout_exercise', CommentTarget.workoutExercise),
      ('exercise_set', CommentTarget.exerciseSet),
      ('workout_image', CommentTarget.workoutImage),
    ]) {
      test('parses $raw', () {
        expect(CommentTarget.fromString(raw), expected);
      });
    }

    for (final raw in ['set', '', 'workouts', 'WORKOUT']) {
      test('throws on $raw', () {
        expect(() => CommentTarget.fromString(raw), throwsA(isA<ArgumentError>()));
      });
    }
  });

  group('CommentTarget column maps to DB FK', () {
    for (final (target, column) in [
      (CommentTarget.workout, 'workout_id'),
      (CommentTarget.workoutExercise, 'workout_exercise_id'),
      (CommentTarget.exerciseSet, 'exercise_set_id'),
      (CommentTarget.workoutImage, 'workout_image_id'),
    ]) {
      test('${target.value} -> $column', () {
        expect(target.column, column);
      });
    }
  });

  group('Comment.fromRow', () {
    test('parses a full row with edited_at', () {
      final created = DateTime.utc(2026, 5, 12, 10);
      final edited = DateTime.utc(2026, 5, 12, 11);
      final c = Comment.fromRow({
        'id': 'c-1',
        'author_id': 'u-1',
        'body': 'looks good',
        'target_type': 'workout',
        'target_id': 'w-1',
        'created_at': created,
        'edited_at': edited,
      });
      expect(c.id, 'c-1');
      expect(c.authorId, 'u-1');
      expect(c.body, 'looks good');
      expect(c.targetType, CommentTarget.workout);
      expect(c.targetId, 'w-1');
      expect(c.createdAt, created);
      expect(c.editedAt, edited);
    });

    test('parses a row without edited_at', () {
      final c = Comment.fromRow({
        'id': 'c-2',
        'author_id': 'u-1',
        'body': 'x',
        'target_type': 'exercise_set',
        'target_id': 's-1',
        'created_at': DateTime.utc(2026, 5, 12),
        'edited_at': null,
      });
      expect(c.editedAt, isNull);
    });

    test('accepts ISO-8601 strings for created_at / edited_at', () {
      final c = Comment.fromRow({
        'id': 'c-3',
        'author_id': 'u-1',
        'body': 'x',
        'target_type': 'workout_exercise',
        'target_id': 'we-1',
        'created_at': '2026-05-12T10:00:00.000Z',
        'edited_at': '2026-05-12T11:00:00.000Z',
      });
      expect(c.createdAt, DateTime.utc(2026, 5, 12, 10));
      expect(c.editedAt, DateTime.utc(2026, 5, 12, 11));
    });
  });

  group('Comment.toMap', () {
    test('round-trips, omitting editedAt when null', () {
      final c = Comment(
        id: 'c-1',
        authorId: 'u-1',
        body: 'nice',
        targetType: .workoutImage,
        targetId: 'i-1',
        createdAt: DateTime.utc(2026, 5, 12),
      );
      expect(c.toMap(), {
        'id': 'c-1',
        'authorId': 'u-1',
        'body': 'nice',
        'targetType': 'workout_image',
        'targetId': 'i-1',
        'createdAt': '2026-05-12T00:00:00.000Z',
      });
    });

    test('includes editedAt when set', () {
      final c = Comment(
        id: 'c-1',
        authorId: 'u-1',
        body: 'nice',
        targetType: .workoutImage,
        targetId: 'i-1',
        createdAt: DateTime.utc(2026, 5, 12),
        editedAt: DateTime.utc(2026, 5, 12, 1),
      );
      expect(c.toMap()['editedAt'], '2026-05-12T01:00:00.000Z');
    });
  });
}
