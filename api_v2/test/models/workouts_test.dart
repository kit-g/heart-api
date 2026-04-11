import 'package:heart/models/workouts.dart';
import 'package:test/test.dart';

void main() {
  group('SetItem', () {
    test('fromRow parses row correctly', () {
      final row = {
        'weight': 100.5,
        'distance': 1.2,
        'reps': 10,
        'duration': 60,
        'id': 'set_1',
        'completed': true,
      };

      final setItem = SetItem.fromRow(row);

      expect(setItem.weight, equals(100.5));
      expect(setItem.distance, equals(1.2));
      expect(setItem.reps, equals(10));
      expect(setItem.duration, equals(60));
      expect(setItem.id, equals('set_1'));
      expect(setItem.completed, isTrue);
    });

    test('fromRow handles mixed num types', () {
      final row = {
        'weight': 100, // int instead of double
        'distance': 1, // int instead of double
        'reps': 10.0, // double instead of int
        'duration': 60.5, // double instead of int
        'id': 'set_1',
        'completed': false,
      };

      final setItem = SetItem.fromRow(row);

      expect(setItem.weight, equals(100.0));
      expect(setItem.distance, equals(1.0));
      expect(setItem.reps, equals(10));
      expect(setItem.duration, equals(60));
      expect(setItem.completed, isFalse);
    });

    test('toMap returns correct map and omits nulls', () {
      final row = {
        'weight': 100.5,
        'distance': null, // Should be omitted
        'reps': 10,
        'duration': null, // Should be omitted
        'id': 'set_1',
        'completed': true,
      };

      final setItem = SetItem.fromRow(row);
      final map = setItem.toMap();

      expect(map['weight'], equals(100.5));
      expect(map.containsKey('distance'), isFalse);
      expect(map['reps'], equals(10));
      expect(map.containsKey('duration'), isFalse);
      expect(map['id'], equals('set_1'));
      expect(map['completed'], isTrue);
    });
  });

  group('ExerciseItem', () {
    test('fromRow parses row correctly', () {
      final row = {
        'id': 'ex_item_1',
        'exercise_id': 'bench_press',
        'exercise_order': 1,
        'sets': [
          {
            'weight': 60.0,
            'reps': 12,
            'id': 'set_1',
            'completed': true,
          },
        ],
      };

      final exerciseItem = ExerciseItem.fromRow(row);

      expect(exerciseItem.id, equals('ex_item_1'));
      expect(exerciseItem.exerciseId, equals('bench_press'));
      expect(exerciseItem.exerciseOrder, equals(1));
      expect(exerciseItem.sets.length, equals(1));
      expect(exerciseItem.sets.first.id, equals('set_1'));
    });

    test('toMap returns correct map', () {
      final row = {
        'id': 'ex_item_1',
        'exercise_id': 'bench_press',
        'exercise_order': 1,
        'sets': [
          {
            'weight': 60.0,
            'reps': 12,
            'id': 'set_1',
            'completed': true,
          },
        ],
      };

      final exerciseItem = ExerciseItem.fromRow(row);
      final map = exerciseItem.toMap();

      expect(map['id'], equals('ex_item_1'));
      expect(map['exercise'], equals('bench_press'));
      expect(map['order'], equals(1));
      expect(map['sets'], isA<List>());
      expect((map['sets'] as List<Map>).first['id'], equals('set_1'));
    });

    test('is Iterable', () {
      final row = {
        'id': 'ex_item_1',
        'exercise_id': 'bench_press',
        'exercise_order': 1,
        'sets': [
          {'id': 's1', 'completed': true},
          {'id': 's2', 'completed': false},
        ],
      };
      final exerciseItem = ExerciseItem.fromRow(row);
      expect(exerciseItem.length, equals(2));
      expect(exerciseItem.first.id, equals('s1'));
      expect(exerciseItem.last.id, equals('s2'));
    });
  });

  group('WorkoutImageItem', () {
    test('constructor parses ID from key', () {
      final image = WorkoutImageItem(
        'users/123/workouts/456/img_789.jpg',
        url: (key) => 'https://cdn/$key',
        workoutId: '456',
      );

      expect(image.key, equals('users/123/workouts/456/img_789.jpg'));
      expect(image.link, equals('https://cdn/users/123/workouts/456/img_789.jpg'));
      expect(image.workoutId, equals('456'));
      expect(image.id, equals('img_789'));
    });

    test('toMap returns correct map', () {
      final image = WorkoutImageItem(
        'img.png',
        url: (key) => 'url/$key',
        workoutId: 'w1',
      );
      final map = image.toMap();

      expect(map['key'], equals('img.png'));
      expect(map['url'], equals('url/img.png'));
      expect(map['id'], equals('img'));
      expect(map['workoutId'], equals('w1'));
    });
  });

  group('WorkoutItem', () {
    final now = DateTime.utc(2024, 1, 1, 10, 0, 0);
    final row = {
      'PK': 'USER#123',
      'SK': 'WORKOUT#456',
      'name': 'Morning Workout',
      'start': now.toIso8601String(),
      'end': now.add(const Duration(hours: 1)).toIso8601String(),
      'exercises': [
        {
          'id': 'ei1',
          'exercise_id': 'ex1',
          'exercise_order': 0,
          'sets': [],
        },
      ],
      'images': ['img1.jpg'],
    };

    test('fromRow parses row correctly', () {
      final workout = WorkoutItem.fromRow(row, imageUrl: (k) => 'url/$k');

      expect(workout.pk, equals('USER#123'));
      expect(workout.sk, equals('WORKOUT#456'));
      expect(workout.id, equals('456'));
      expect(workout.name, equals('Morning Workout'));
      expect(workout.start, equals(now));
      expect(workout.end, equals(now.add(const Duration(hours: 1))));
      expect(workout.exercises.length, equals(1));
      expect(workout.images?.length, equals(1));
      expect(workout.images?.first.id, equals('img1'));
    });

    test('fromRow handles null end and images', () {
      final minimalRow = {
        'PK': 'USER#123',
        'SK': 'WORKOUT#456',
        'name': 'Morning Workout',
        'start': now.toIso8601String(),
        'exercises': null,
        'images': null,
      };

      final workout = WorkoutItem.fromRow(minimalRow, imageUrl: (k) => 'url/$k');

      expect(workout.end, isNull);
      expect(workout.exercises, isEmpty);
      expect(workout.images, isNull);
    });

    test('toMap returns correct map and omits nulls', () {
      final minimalRow = {
        'PK': 'USER#123',
        'SK': 'WORKOUT#456',
        'name': 'Morning Workout',
        'start': now.toIso8601String(),
        'exercises': null,
        'images': null,
      };

      final workout = WorkoutItem.fromRow(minimalRow, imageUrl: (k) => 'url/$k');
      final map = workout.toMap();

      expect(map['name'], equals('Morning Workout'));
      expect(map['id'], equals('456'));
      expect(map['start'], equals(now.toIso8601String()));
      expect(map.containsKey('end'), isFalse);
      expect(map['exercises'], isEmpty);
      expect(map.containsKey('images'), isFalse);
    });

    test('is Iterable', () {
      final workout = WorkoutItem.fromRow(row, imageUrl: (k) => 'url/$k');
      expect(workout.length, equals(1));
      expect(workout.first.id, equals('ei1'));
    });
  });

  group('WorkoutListResponse', () {
    test('toMap returns correct map', () {
      final now = DateTime.utc(2024, 1, 1);
      final workout = WorkoutItem.fromRow({
        'PK': 'U',
        'SK': 'W#1',
        'name': 'W1',
        'start': now.toIso8601String(),
      }, imageUrl: (k) => k);

      final response = WorkoutListResponse(workouts: [workout], cursor: 'next_token');
      final map = response.toMap();

      expect(map['workouts'], isA<List>());
      expect((map['workouts'] as List).length, equals(1));
      expect(map['cursor'], equals('next_token'));
    });

    test('is Iterable', () {
      final now = DateTime.utc(2024, 1, 1);
      final workout = WorkoutItem.fromRow({
        'PK': 'U',
        'SK': 'W#1',
        'name': 'W1',
        'start': now.toIso8601String(),
      }, imageUrl: (k) => k);

      final response = WorkoutListResponse(workouts: [workout], cursor: null);
      expect(response.length, equals(1));
      expect(response.first.name, equals('W1'));
    });
  });
}
