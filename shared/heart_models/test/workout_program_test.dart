import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('the template and program a workout was started from (heart-api#215)', () {
    test('a template starts a workout that names it and its program', () {
      final template = Template.fromJson(const {'id': 't1', 'order': 0, 'programId': 'p1'});
      final workout = template.toWorkout();
      expect(workout.templateId, 't1');
      expect(workout.programId, 'p1');
      expect(workout.toMap(), allOf(containsPair('templateId', 't1'), containsPair('programId', 'p1')));
    });

    test('round-trips through the wire and the row', () {
      final json = Workout.fromExercises(const [], templateId: 't1', programId: 'p1').toMap();
      final read = Workout.fromJson(json);
      expect((read.templateId, read.programId), ('t1', 'p1'));

      final row = Workout.fromRow({
        'id': 'w1',
        'name': 'A',
        'started_at': DateTime.utc(2026, 10, 14),
        'template_id': 't1',
        'program_id': 'p1',
      }, imageUrl: (key) => key);
      expect((row.templateId, row.programId), ('t1', 'p1'));
    });

    test('left out when null, so a save never detaches one', () {
      final map = Workout().toMap();
      expect(map.containsKey('templateId'), isFalse);
      expect(map.containsKey('programId'), isFalse);
    });

    test('the same session keeps them; a repeat starts without them', () {
      final workout = Workout.fromExercises(const [], templateId: 't1', programId: 'p1');
      expect(workout.copy(sameId: true).programId, 'p1');
      final repeat = workout.copy();
      expect(repeat.templateId, isNull);
      expect(repeat.programId, isNull);
    });
  });
}
