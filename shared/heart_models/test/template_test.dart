import 'package:test/test.dart';
import 'package:heart_models/heart_models.dart';

void main() {
  group(
    'Template Tests',
    () {
      test(
        'empty constructor creates a Template with no exercises',
        () {
          final template = Template.empty(id: 'template_1', order: 1);

          expect(template.id, 'template_1');
          expect(template.order, 1);
          expect(template.name, isNull);
          expect(template.isEmpty, true);
        },
      );

      test(
        'toWorkout converts Template to a Workout',
        () {
          final template = Template.empty(id: 'template_3', order: 3);
          final workout = template.toWorkout();

          expect(workout, isEmpty);
        },
      );

      test(
        'a template written by its owner carries no assignment metadata',
        () {
          final template = Template.empty(id: 'template_7', order: 0);

          expect(template.isAssigned, isFalse);
          expect(template.assignedBy, isNull);
          expect(template.sourceTemplateId, isNull);
          expect(template.folderId, isNull);
        },
      );

      test(
        'fromRow surfaces the folder and who assigned the template',
        () {
          final template = Template.fromRow({
            'id': 'template_8',
            'name': 'Push',
            'order_index': 0,
            'folder_id': 'folder-1',
            'source_template_id': 'master-1',
            'assigned_by_id': 'coach-1',
            'assigned_by_username': 'Coach',
            'assigned_by_avatar': 'https://example.test/a.png',
            'sync_enabled': true,
          });

          expect(template.folderId, 'folder-1');
          expect(template.sourceTemplateId, 'master-1');
          expect(template.isAssigned, isTrue);
          expect(template.assignedBy?.id, 'coach-1');
          expect(template.assignedBy?.name, 'Coach');
          expect(template.syncEnabled, isTrue);
        },
      );

      test(
        'toMap carries the new fields but toRow stays at the app\'s SQLite columns',
        () {
          final template = Template.fromRow({
            'id': 'template_9',
            'name': 'Push',
            'order_index': 1,
            'folder_id': 'folder-1',
            'assigned_by_id': 'coach-1',
            'assigned_by_username': 'Coach',
          });

          expect(template.toMap()['folderId'], 'folder-1');
          expect((template.toMap()['assignedBy'] as Map)['id'], 'coach-1');
          // The app spreads toRow() into an INSERT; an extra key breaks it.
          expect(template.toRow().keys, unorderedEquals(['id', 'name', 'order_in_parent']));
        },
      );

      test(
        'toMap omits the assignment fields when there are none',
        () {
          final map = Template.empty(id: 'template_10', order: 0).toMap();

          expect(map.containsKey('folderId'), isFalse);
          expect(map.containsKey('assignedBy'), isFalse);
          expect(map.containsKey('sourceTemplateId'), isFalse);
          expect(map.containsKey('syncEnabled'), isFalse);
        },
      );

      test(
        'fromJson tolerates a payload with none of the new keys',
        () {
          final template = Template.fromJson({'id': 'template_11', 'order': 0, 'name': 'Legacy'});

          expect(template.folderId, isNull);
          expect(template.isAssigned, isFalse);
        },
      );

      test(
        'Comparison works correctly',
        () {
          final template1 = Template.empty(id: 'template_4', order: 1);
          final template2 = Template.empty(id: 'template_5', order: 2);
          final template3 = Template.empty(id: 'template_6', order: 1);

          expect(template1.compareTo(template2) < 0, true);
          expect(template2.compareTo(template1) > 0, true);
          // when orders tie, fall back to id ordering
          expect(template1.compareTo(template3) < 0, true);
          expect(template3.compareTo(template1) > 0, true);
          expect(template1.compareTo(template1) == 0, true);
        },
      );
    },
  );
}
