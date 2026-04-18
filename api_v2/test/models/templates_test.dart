import 'package:heart/models/profile.dart';
import 'package:heart/models/templates.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateItem', () {
    final exerciseRow = {
      'id': 'ex_1',
      'exercise_id': 'bench_press',
      'exercise_order': 1,
      'sets': [
        {'id': 'set_1', 'weight': 100.0, 'reps': 8, 'completed': true},
      ],
    };

    final fullRow = {
      'SK': 'TEMPLATE#template_123',
      'name': 'Push Day',
      'order': 1,
      'exercises': [exerciseRow],
      'source_template_id': 'master_id',
      'assigned_by': {
        'PK': 'USER#coach_id',
        'SK': 'USER#coach_id',
        'username': 'Coach Name',
        'avatar': null,
      },
      'sync_enabled': true,
    };

    test('fromRow parses all fields', () {
      final item = TemplateItem.fromRow(fullRow);

      expect(item.id, equals('template_123'));
      expect(item.name, equals('Push Day'));
      expect(item.order, equals(1));
      expect(item.exercises.length, equals(1));
      expect(item.sourceTemplateId, equals('master_id'));
      expect(item.syncEnabled, isTrue);
      expect(item.assignedBy, isNotNull);
      expect(item.assignedBy!.name, equals('Coach Name'));
    });

    test('fromRow applies defaults for missing optional fields', () {
      final item = TemplateItem.fromRow({
        'SK': 'TEMPLATE#template_456',
        'name': 'Minimal',
        'exercises': [],
      });

      expect(item.id, equals('template_456'));
      expect(item.order, equals(0));
      expect(item.sourceTemplateId, isNull);
      expect(item.assignedBy, isNull);
    });

    test('toMap serializes correctly', () {
      final item = TemplateItem.fromRow(fullRow);
      final map = item.toMap();

      expect(map['id'], equals('template_123'));
      expect(map['name'], equals('Push Day'));
      expect(map['order'], equals(1));
      expect(map['syncEnabled'], isTrue);
      expect(map['sourceTemplateId'], equals('master_id'));
      expect((map['exercises'] as List).length, equals(1));
      expect(map['assignedBy'], isNotNull);
    });

    test('is iterable over exercises', () {
      final item = TemplateItem.fromRow(fullRow);

      expect(item.length, equals(1));
      expect(item.first.id, equals('ex_1'));
    });

    test('copyWith updates specified fields', () {
      final item = TemplateItem.fromRow(fullRow);
      final updated = item.copyWith(name: 'Leg Day', order: 3);

      expect(updated.name, equals('Leg Day'));
      expect(updated.order, equals(3));
      expect(updated.id, equals('template_123'));
      expect(updated.sourceTemplateId, equals('master_id'));
    });
  });

  group('TemplateShareItem', () {
    final assignedAt = DateTime.utc(2025, 1, 1, 12, 0, 0);

    final row = {
      'SK': 'TEMPLATE_SHARE#master_id#student_id',
      'student_template_id': '2025-01-01T12:00:00.000Z',
      'template_name': 'Push Day',
      'assigned_to': {
        'PK': 'USER#student_id',
        'SK': 'USER#student_id',
        'username': 'Student Name',
        'avatar': null,
      },
      'assigned_at': assignedAt.toIso8601String(),
    };

    test('fromRow parses all fields', () {
      final item = TemplateShareItem.fromRow(row);

      expect(item.id, equals('student_id|master_id'));
      expect(item.studentTemplateId, equals('2025-01-01T12:00:00.000Z'));
      expect(item.templateName, equals('Push Day'));
      expect(item.assignedTo.name, equals('Student Name'));
      expect(item.assignedAt, equals(assignedAt));
    });

    test('fromRow throws on invalid SK format', () {
      expect(
        () => TemplateShareItem.fromRow({...row, 'SK': 'INVALID'}),
        throwsArgumentError,
      );
    });

    test('toMap serializes correctly', () {
      final item = TemplateShareItem.fromRow(row);
      final map = item.toMap();

      expect(map['studentTemplateId'], equals('2025-01-01T12:00:00.000Z'));
      expect(map['templateName'], equals('Push Day'));
      expect(map['assignedAt'], equals(assignedAt.toIso8601String()));
      expect((map['assignedTo'] as Map)['name'], equals('Student Name'));
    });

    test('direct constructor creates item', () {
      final profile = Profile.fromJson({
        'PK': 'USER#student_id',
        'SK': 'USER#student_id',
        'username': 'Student Name',
      });
      final item = TemplateShareItem(
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
      final item = TemplateShareItem.fromRow(row);
      final updated = item.copyWith(templateName: 'Updated Name');

      expect(updated.templateName, equals('Updated Name'));
      expect(updated.id, equals(item.id));
      expect(updated.assignedTo.name, equals('Student Name'));
    });
  });

  group('TemplateListResponse', () {
    test('toMap includes cursor when present', () {
      final response = TemplateListResponse(templates: [], cursor: 'abc123');
      final map = response.toMap();

      expect(map['templates'], isEmpty);
      expect(map['cursor'], equals('abc123'));
    });

    test('toMap omits cursor when null', () {
      final response = TemplateListResponse(templates: [], cursor: null);

      expect(response.toMap().containsKey('cursor'), isFalse);
    });

    test('is iterable', () {
      final response = TemplateListResponse(templates: [], cursor: null);

      expect(response.isEmpty, isTrue);
    });
  });

  group('TemplateShareListResponse', () {
    test('toMap includes cursor when present', () {
      final response = TemplateShareListResponse(shares: [], cursor: 'xyz');
      final map = response.toMap();

      expect(map['shares'], isEmpty);
      expect(map['cursor'], equals('xyz'));
    });

    test('toMap omits cursor when null', () {
      final response = TemplateShareListResponse(shares: [], cursor: null);

      expect(response.toMap().containsKey('cursor'), isFalse);
    });

    test('is iterable', () {
      final response = TemplateShareListResponse(shares: [], cursor: null);

      expect(response.isEmpty, isTrue);
    });
  });
}