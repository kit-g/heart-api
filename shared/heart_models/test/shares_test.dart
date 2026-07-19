import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateShare', () {
    final assignedAt = DateTime.utc(2025, 1, 1, 12, 0, 0);

    final row = {
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

      expect(item.id, equals('student_id|master_id'));
      expect(item.studentTemplateId, equals('student_template_id'));
      expect(item.templateName, equals('Push Day'));
      expect(item.assignedTo.id, equals('student_id'));
      expect(item.assignedTo.name, equals('Student Name'));
      expect(item.assignedAt, equals(assignedAt));
    });

    test('toMap serializes correctly', () {
      final item = TemplateShare.fromRow(row);
      final map = item.toMap();

      expect(map['studentTemplateId'], equals('student_template_id'));
      expect(map['templateName'], equals('Push Day'));
      expect(map['assignedAt'], equals(assignedAt.toIso8601String()));
      expect((map['assignedTo'] as Map)['name'], equals('Student Name'));
    });

    test('direct constructor creates item', () {
      final profile = Profile.fromJson({'id': 'student_id', 'username': 'Student Name', 'avatar': null});
      final item = TemplateShare(
        id: 'student_id|template_id',
        studentTemplateId: 'ts_1',
        templateName: 'Push Day',
        assignedTo: profile,
        assignedAt: assignedAt,
      );

      expect(item.id, equals('student_id|template_id'));
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
