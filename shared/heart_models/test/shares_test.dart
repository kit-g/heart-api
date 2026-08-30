import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateRequest', () {
    List<dynamic> exercisesOf(TemplateRequest request) {
      return jsonDecode(request.toParams()['exercises'] as String) as List;
    }

    test('toParams maps onto the names _saveTemplate binds', () {
      final params = const TemplateRequest(userId: 'u1', name: 'Push', order: 2, folderId: 'f-1').toParams();

      expect(params['userId'], 'u1');
      expect(params['name'], 'Push');
      expect(params['orderIndex'], 2);
      expect(params['folderId'], 'f-1');
      // movesFolder is update-only and bound separately; including it here makes
      // the driver reject the create statement as having a superfluous variable.
      expect(params.containsKey('movesFolder'), isFalse);
    });

    test('an empty template encodes an empty exercise array, not null', () {
      expect(const TemplateRequest(userId: 'u1').toParams()['exercises'], '[]');
    });

    test('exercises encode with the snake_case keys the jsonb is read by', () {
      final request = const TemplateRequest(
        userId: 'u1',
        exercises: [
          TemplateExerciseRequest(
            exerciseId: '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6',
            order: 0,
            sets: [TemplateSetRequest(weight: 60, reps: 5)],
          ),
        ],
      );

      final encoded = exercisesOf(request).single as Map;
      expect(encoded['exercise_id'], '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6');
      expect(encoded['order'], 0);
      expect((encoded['sets'] as List).single, {'weight': 60, 'reps': 5});
    });

    test('a set omits the measures it does not have', () {
      final request = const TemplateRequest(
        userId: 'u1',
        exercises: [
          TemplateExerciseRequest(
            exerciseId: '0198c1a2-b3c4-7d5e-8f60-718293a4b5c7',
            order: 0,
            sets: [TemplateSetRequest(duration: 60)],
          ),
        ],
      );

      final set = ((exercisesOf(request).single as Map)['sets'] as List).single as Map;
      expect(set, {'duration': 60});
    });
  });

  group('TemplateShare', () {
    final assignedAt = DateTime.utc(2025, 1, 1, 12, 0, 0);

    final row = {
      'id': 'share-uuid-1',
      'student_id': 'student_id',
      'master_template_id': 'master_id',
      'student_template_id': 'student_template_id',
      'template_name': 'Push Day',
      'student_username': 'Student Name',
      'student_avatar': null,
      'created_at': assignedAt,
    };

    test('fromRow parses all fields', () {
      final item = TemplateShare.fromRow(row);

      expect(item.id, equals('share-uuid-1'));
      expect(item.masterTemplateId, equals('master_id'));
      expect(item.studentTemplateId, equals('student_template_id'));
      expect(item.templateName, equals('Push Day'));
      expect(item.assignedTo.id, equals('student_id'));
      expect(item.assignedTo.name, equals('Student Name'));
      expect(item.assignedAt, equals(assignedAt));
    });

    test('toMap serializes correctly', () {
      final item = TemplateShare.fromRow(row);
      final map = item.toMap();

      expect(map['masterTemplateId'], equals('master_id'));
      expect(map['studentTemplateId'], equals('student_template_id'));
      expect(map['templateName'], equals('Push Day'));
      expect(map['assignedAt'], equals(assignedAt.toIso8601String()));
      expect((map['assignedTo'] as Map)['name'], equals('Student Name'));
    });

    test('direct constructor creates item', () {
      final profile = Profile.fromJson({'id': 'student_id', 'username': 'Student Name', 'avatar': null});
      final item = TemplateShare(
        id: 'share-uuid-2',
        masterTemplateId: 'master_id',
        studentTemplateId: 'ts_1',
        templateName: 'Push Day',
        assignedTo: profile,
        assignedAt: assignedAt,
      );

      expect(item.id, equals('share-uuid-2'));
      expect(item.assignedTo.name, equals('Student Name'));
    });

    test('copyWith updates specified fields', () {
      final item = TemplateShare.fromRow(row);
      final updated = item.copyWith(templateName: 'Updated Name');

      expect(updated.templateName, equals('Updated Name'));
      expect(updated.id, equals(item.id));
      expect(updated.assignedTo.name, equals('Student Name'));
    });
  });
}
