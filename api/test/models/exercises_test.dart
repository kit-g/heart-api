import 'package:heart/models/exercises.dart';
import 'package:test/test.dart';

void main() {
  group('ExerciseModel', () {
    test('toMap returns the row map verbatim', () {
      final row = {
        'id': 'ex_1',
        'name': 'Bench Press (Barbell)',
        'category': 'Barbell',
        'target': 'Chest',
        'instructions': 'do it',
        'archived': false,
        'own': true,
      };
      expect(ExerciseModel(row).toMap(), row);
    });

    test('toMap allows null fields (asset, thumbnail) to pass through', () {
      final row = {
        'id': 'ex_1',
        'name': 'Squat (Barbell)',
        'asset': null,
        'thumbnail': null,
      };
      expect(ExerciseModel(row).toMap()['asset'], isNull);
      expect(ExerciseModel(row).toMap()['thumbnail'], isNull);
    });
  });

  group('ExerciseResponse', () {
    test('toMap returns the underlying library map', () {
      final lib = {
        'exercises': [
          {'id': 'a', 'name': 'A'},
          {'id': 'b', 'name': 'B'},
        ],
      };
      expect(ExerciseResponse(exerciseLibrary: lib).toMap(), lib);
    });

    test('handles empty library', () {
      final response = ExerciseResponse(exerciseLibrary: {'exercises': []});
      expect(response.toMap()['exercises'], isEmpty);
    });
  });
}