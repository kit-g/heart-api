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
