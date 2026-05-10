import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'mocks.mocks.dart';

void main() {
  late MockExercise mockExercise;

  setUp(
    () {
      mockExercise = MockExercise();

      when(mockExercise.name).thenReturn('Mock Exercise');
      when(mockExercise.category).thenReturn(Category.weightedBodyWeight);
      when(mockExercise.target).thenReturn(Target.chest);
    },
  );

  ExerciseSet setFactory({int reps = 10, double weight = 50, bool isCompleted = false}) {
    return ExerciseSet(
      mockExercise,
      start: DateTime.now(),
      reps: reps,
      weight: weight,
    )..isCompleted = isCompleted;
  }

  group(
    'ExerciseSet Tests',
    () {
      test(
        'ExerciseSet is created correctly',
        () {
          final startTime = DateTime.parse('2025-01-21T12:00:00Z');
          final set = ExerciseSet(
            mockExercise,
            reps: 12,
            weight: 75.0,
            start: startTime,
          );

          expect(set.exercise, equals(mockExercise));
          expect(set.start, equals(startTime));
          expect(set.isCompleted, equals(false));
        },
      );

      test(
        'toMap works for ExerciseSet',
        () {
          final startTime = DateTime.parse('2025-01-21T12:00:00Z');
          final weightedSet = ExerciseSet(
            mockExercise,
            reps: 8,
            weight: 100.0,
            start: startTime,
          );

          final map = weightedSet.toMap();

          expect(
            map,
            equals(
              {
                'id': startTime.toIso8601String(),
                'completed': false,
                'reps': 8,
                'weight': 100.0,
              },
            ),
          );
        },
      );

      test(
        'Comparison operators work for ExerciseSet',
        () {
          final set1 = ExerciseSet(mockExercise, reps: 10, weight: 50.0);
          final set2 = ExerciseSet(mockExercise, reps: 8, weight: 60.0);

          expect(set1.total! > set2.total!, equals(true));
          expect(set1.total! >= set2.total!, equals(true));

          expect(
            ExerciseSet(mockExercise, reps: 10, weight: 50.0).total! >
                ExerciseSet(mockExercise, reps: 50, weight: 10.0).total!,
            isFalse,
          );

          expect(
            ExerciseSet(mockExercise, reps: 10, weight: 50.0).total! >=
                ExerciseSet(mockExercise, reps: 50, weight: 10.0).total!,
            isTrue,
          );

          expect(
            ExerciseSet(mockExercise, reps: 10, weight: 50.0).total! <=
                ExerciseSet(mockExercise, reps: 50, weight: 10.0).total!,
            isTrue,
          );
        },
      );

      test(
        'Copy creates a new instance of ExerciseSet',
        () {
          final original = ExerciseSet(
            mockExercise,
            reps: 12,
            weight: 60.0,
            start: DateTime.parse('2025-01-21T12:00:00Z'),
          );

          final copy = original.copy();

          expect(copy.exercise, original.exercise);
          expect(copy.total, original.total);
          expect(copy.id, isNot(equals(original.id)));
          expect(identical(copy, original), isFalse);
        },
      );

      test(
        'Factory constructor creates from JSON',
        () {
          final json = {
            'id': 'set-uuid',
            'started_at': '2025-01-21T12:00:00Z',
            'reps': 15,
            'weight': 80.0,
            'completed': true,
          };

          final exerciseSet = ExerciseSet.fromJson(mockExercise, json);

          expect(exerciseSet.exercise, equals(mockExercise));
          expect(exerciseSet.id, equals('set-uuid'));
          expect(exerciseSet.start, equals(DateTime.parse('2025-01-21T12:00:00Z')));
          expect(exerciseSet.isCompleted, equals(true));
        },
      );
    },
  );

  group(
    'WorkoutExercise Tests',
    () {
      late ExerciseSet starterSet;

      setUp(
        () {
          starterSet = setFactory();
        },
      );

      test(
        'WorkoutExercise is initialized with a starter set',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);

          expect(workoutExercise.exercise, equals(mockExercise));
          expect(workoutExercise.sets, contains(starterSet));
          expect(workoutExercise.total, equals(500.0));
          expect(workoutExercise.isStarted, equals(false));
        },
      );

      test(
        'Adding a set increases the number of sets',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);
          final anotherSet = ExerciseSet(
            mockExercise,
            reps: 8,
            weight: 60.0,
            start: DateTime.now(),
          );

          workoutExercise.add(anotherSet);

          expect(workoutExercise.sets, contains(anotherSet));
          expect(workoutExercise.total, equals(980.0)); // 500 + 480
          expect(workoutExercise.isStarted, equals(false));
        },
      );

      test(
        'Removing a set decreases the number of sets',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);
          workoutExercise.remove(starterSet);

          expect(workoutExercise.sets, isEmpty);
          expect([null, 0.0], contains(workoutExercise.total));
        },
      );

      test(
        'Best set is calculated correctly',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);
          final betterSet = ExerciseSet(
            mockExercise,
            reps: 12,
            weight: 55.0,
            start: DateTime.now(),
          );

          workoutExercise.add(betterSet);

          expect(workoutExercise.best, equals(betterSet));
        },
      );

      test(
        'Order can be set and retrieved',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);

          workoutExercise.order = 1;
          expect(workoutExercise.order, equals(1));

          workoutExercise.order = null;
          expect(workoutExercise.order, isNull);
        },
      );

      test(
        'isStarted returns true when at least one set is completed',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet);
          final completedSet = ExerciseSet(
            mockExercise,
            reps: 8,
            weight: 60.0,
            start: DateTime.now(),
          )..isCompleted = true;

          workoutExercise.add(completedSet);

          expect(workoutExercise.isStarted, isTrue);
        },
      );

      test(
        'isCompleted returns true when all sets are completed',
        () {
          final workoutExercise = WorkoutExercise(starter: starterSet..isCompleted = true);
          expect(workoutExercise.isCompleted, isTrue);

          final incompleteSet = setFactory();
          workoutExercise.add(incompleteSet);
          expect(workoutExercise.isCompleted, isFalse);
        },
      );

      test(
        'compareTo orders by set order when available',
        () {
          final first = WorkoutExercise(starter: starterSet)..order = 1;
          final second = WorkoutExercise(starter: starterSet)..order = 2;
          final unordered = WorkoutExercise(starter: starterSet);

          expect(first.compareTo(second) < 0, isTrue);
          expect(second.compareTo(first) > 0, isTrue);

          // When one or both don't have an order, falls back to timestamp comparison
          expect(first.compareTo(unordered) != 0, isTrue);
        },
      );

      test(
        'toMap returns correct structure for WorkoutExercise',
        () {
          final exerciseMap = {'name': 'Mock Exercise'};
          when(mockExercise.toMap()).thenReturn(exerciseMap);

          final workoutExercise = WorkoutExercise(starter: starterSet..isCompleted = true);
          final map = workoutExercise.toMap();

          expect(map['id'], equals(workoutExercise.id));
          expect(map['exercise'], equals(exerciseMap));
          expect(map['sets'], isA<List>());
          expect(map['sets'][0]['id'], starterSet.id);
        },
      );
    },
  );

  group(
    'Workout Tests',
    () {
      late ExerciseSet starterSet;
      late ExerciseSet completedSet;
      late WorkoutExercise workoutExercise;
      late Workout workout;

      setUp(
        () {
          starterSet = setFactory();
          completedSet = setFactory(reps: 8, weight: 60, isCompleted: true);
          workoutExercise = WorkoutExercise(starter: starterSet);

          workout = Workout(name: 'Mock Workout');
        },
      );

      test(
        'Workout is initialized with a name',
        () {
          expect(workout.name, equals('Mock Workout'));
          expect(workout.isCompleted, isFalse);
          expect(workout.duration, isNull);
          expect(workout.total, isNull);
          expect(workout.isStarted, isFalse);
          expect(workout.isValid, isFalse);
          expect(workout.end, isNull);
        },
      );

      test(
        'Appending a WorkoutExercise adds it to the workout',
        () {
          workout.append(workoutExercise);

          expect(workout.sets.length, equals(1));
          expect(workout.sets, contains(workoutExercise));
        },
      );

      test(
        'Removing a WorkoutExercise updates the workout',
        () {
          workout.append(workoutExercise);
          workout.remove(workoutExercise);

          expect(workout.sets, isEmpty);
        },
      );

      test(
        'Workout total calculates correctly',
        () {
          final additionalSet = ExerciseSet(
            mockExercise,
            reps: 12,
            weight: 60.0,
            start: DateTime.now(),
          );

          final additionalExercise = WorkoutExercise(starter: additionalSet);

          workout.append(workoutExercise);
          workout.append(additionalExercise);

          expect(workout.total, equals(workoutExercise.total! + additionalExercise.total!));
        },
      );

      test(
        'Marking a workout as complete sets end time and isCompleted',
        () {
          final endTime = DateTime.now();

          workout.finish(endTime);

          expect(workout.end, equals(endTime));
          expect(workout.isCompleted, isTrue);
        },
      );

      test(
        'Duration is calculated correctly after workout is finished',
        () {
          final startTime = DateTime.now();
          final endTime = startTime.add(const Duration(hours: 1));

          workout.finish(endTime);

          expect(workout.duration?.inSeconds, equals(3600));
        },
      );

      test(
        'isStarted returns true if at least one set is completed',
        () {
          workout.append(workoutExercise);
          workoutExercise.add(completedSet);
          expect(workout.isStarted, equals(true));
        },
      );

      test(
        'isStarted returns false if no sets are completed',
        () {
          workout.append(workoutExercise);

          expect(workout.isStarted, equals(false));
        },
      );

      test(
        'isValid returns true if all sets are completed',
        () async {
          expect(workout.isEmpty, isTrue);

          for (final _ in List.generate(5, (_) => 1)) {
            var exercise = WorkoutExercise(starter: starterSet);
            workout.append(exercise);
            await 10.milliseconds;
          }

          expect(workout.isValid, equals(false)); // Not all sets are complete yet.

          for (final exercise in workout) {
            for (final set in exercise) {
              set.isCompleted = true;
            }
          }

          expect(workout.isValid, equals(true));
        },
      );

      test(
        'startExercise adds a new exercise to the workout',
        () {
          workout.add(mockExercise);

          expect(workout.sets.length, equals(1));
          expect(workout.sets.first.exercise, equals(mockExercise));
        },
      );

      test(
        'swap reorders exercises correctly',
        () {
          final secondExercise = WorkoutExercise(
            starter: ExerciseSet(
              mockExercise,
              reps: 15,
              weight: 40.0,
              start: DateTime.now(),
            ),
          );

          workout.append(workoutExercise);
          workout.append(secondExercise);

          workout.swap(secondExercise, workoutExercise);

          final exercises = workout.sets.toList();
          expect(exercises.first, equals(secondExercise));
          expect(exercises.last, equals(workoutExercise));
        },
      );

      test(
        'nextIncomplete returns the next incomplete set and exercise',
        () {
          workout.append(workoutExercise);

          workoutExercise.add(completedSet);

          final next = workout.nextIncomplete(workoutExercise, completedSet);

          expect(next, isNotNull);
          expect(next!.$2.isCompleted, equals(false));
        },
      );

      test(
        'toSummary creates a valid summary',
        () {
          workout.append(workoutExercise);

          final summary = workout.toSummary();

          expect(summary.id, equals(workout.id));
          expect(summary.name, equals(workout.name));
        },
      );

      test(
        'copy creates a new instance with new timestamps',
        () {
          workout.append(workoutExercise);
          final copy = workout.copy();

          expect(copy.id, isNot(equals(workout.id)));
          expect(copy.name, equals(workout.name));
          expect(copy.sets.length, equals(workout.sets.length));

          final originalExercise = workout.first;
          final copiedExercise = copy.first;

          expect(copiedExercise.id, isNot(equals(originalExercise.id)));
        },
      );

      test(
        'copy with sameId keeps the same id',
        () {
          workout.append(workoutExercise);
          final copy = workout.copy(sameId: true);

          expect(copy.id, equals(workout.id));
        },
      );

      test(
        'completeAllSets marks all sets as completed',
        () {
          workout.append(workoutExercise);
          final incompleteSet = setFactory();
          workoutExercise.add(incompleteSet);

          expect(workout.isValid, isFalse);

          workout.completeAllSets();

          expect(workout.isValid, isTrue);
          for (final exercise in workout) {
            for (final set in exercise) {
              expect(set.isCompleted, isTrue);
            }
          }
        },
      );

      test(
        'removeEmptySets removes incomplete sets and empty exercises',
        () {
          final incompleteSet1 = setFactory(isCompleted: false);
          final incompleteSet2 = setFactory(isCompleted: false);

          workout.append(workoutExercise);
          workoutExercise
            ..add(incompleteSet1)
            ..add(incompleteSet2)
            ..add(completedSet);

          // another exercise that has no complete sets
          final emptyExercise = WorkoutExercise(starter: setFactory(isCompleted: false));
          emptyExercise.add(setFactory(isCompleted: false));
          workout.append(emptyExercise);

          expect(workout.sets.length, equals(2));

          workout.removeEmptySets();

          // emptyExercise should be removed entirely
          expect(workout.sets.length, equals(1));

          // workoutExercise should only have the completedSet left
          expect(workout.first.sets.length, equals(1));
          expect(workout.first.sets.first, equals(completedSet));
        },
      );

      test(
        'removeEmptySets leaves completed workouts intact',
        () {
          workout.append(workoutExercise);
          workoutExercise.add(completedSet);

          // mark the starter set as complete too
          starterSet.isCompleted = true;

          expect(workout.sets.length, equals(1));
          expect(workout.first.sets.length, equals(2));

          workout.removeEmptySets();

          expect(workout.sets.length, equals(1));
          expect(workout.first.sets.length, equals(2));
        },
      );

      test(
        'fromJson creates a workout from JSON data',
        () {
          final json = {
            'id': 'workout-123',
            'name': 'Test Workout',
            'start': '2025-01-21T12:00:00Z',
            'end': '2025-01-21T14:00:00Z',
            'exercises': [
              {
                'id': 'we-1',
                'exercise': {
                  'name': 'Bench Press',
                  'category': 'Barbell',
                  'target': 'Chest',
                },
                'order': 0,
                'sets': [
                  {
                    'id': 'set-1',
                    'reps': 10,
                    'weight': 100.0,
                    'completed': true,
                  },
                ],
              },
            ],
          };

          final workout = Workout.fromJson(json);

          expect(workout.id, equals('workout-123'));
          expect(workout.name, equals('Test Workout'));
          expect(workout.sets.length, equals(1));
          expect(workout.first.exercise.name, equals('Bench Press'));
          expect(workout.first.length, equals(1));
          expect(workout.isCompleted, isTrue);
        },
      );

      test(
        'toString returns workout name or date format',
        () {
          final namedWorkout = Workout(name: 'Named Workout');
          expect(namedWorkout.toString(), equals('Named Workout'));

          final unnamedWorkout = Workout(name: null);
          expect(unnamedWorkout.toString(), startsWith('Workout on'));
        },
      );
    },
  );

  group(
    'WorkoutImage Tests',
    () {
      test(
        'fromJson maps workoutId/photoId/image correctly',
        () {
          final json = <String, dynamic>{
            'workoutId': 'workout-123',
            'id': 'photo-456',
            'url': 'https://example.com/image.jpg',
            'key': 'image.jpg',
          };

          final image = WorkoutImage.fromJson(json);

          expect(image.workoutId, equals('workout-123'));
          expect(image.id, equals('photo-456'));
          expect(image.link, equals('https://example.com/image.jpg'));
          expect(image.key, equals('image.jpg'));
        },
      );

      test(
        'fromJson allows extra keys without affecting mapping',
        () {
          final json = <String, dynamic>{
            'workoutId': 'workout-123',
            'id': 'photo-456',
            'url': 'https://example.com/image.jpg',
            'key': 'image.jpg',
            'extra': {'ignored': true},
          };

          final image = WorkoutImage.fromJson(json);

          expect(image.workoutId, equals('workout-123'));
          expect(image.id, equals('photo-456'));
          expect(image.link, equals('https://example.com/image.jpg'));
        },
      );
    },
  );

  group(
    'ProgressGalleryResponse Tests',
    () {
      test(
        'fromJson parses images list and cursor',
        () {
          final json = <String, dynamic>{
            'cursor': 'next-cursor',
            'images': [
              {
                'workoutId': 'w1',
                'id': 'p1',
                'url': 'https://example.com/1.jpg',
                'key': '1.jpg',
              },
              {
                'workoutId': 'w2',
                'id': 'p2',
                'url': 'https://example.com/2.jpg',
                'key': '1.jpg',
              },
            ],
          };

          final response = ProgressGalleryResponse.fromJson(json);

          expect(response.cursor, equals('next-cursor'));
          expect(response.images.length, equals(2));

          final first = response.images.first;
          expect(first.workoutId, equals('w1'));
          expect(first.id, equals('p1'));
          expect(first.link, equals('https://example.com/1.jpg'));

          final second = response.images.skip(1).first;
          expect(second.workoutId, equals('w2'));
          expect(second.id, equals('p2'));
          expect(second.link, equals('https://example.com/2.jpg'));
        },
      );

      test(
        'fromJson returns empty images when images key is missing',
        () {
          final json = <String, dynamic>{'cursor': 'c'};

          final response = ProgressGalleryResponse.fromJson(json);

          expect(response.cursor, equals('c'));
          expect(response.images, isEmpty);
        },
      );

      test(
        'fromJson returns empty images when images is not a List',
        () {
          final json = <String, dynamic>{
            'cursor': 'c',
            'images': {'not': 'a list'},
          };

          final response = ProgressGalleryResponse.fromJson(json);

          expect(response.cursor, equals('c'));
          expect(response.images, isEmpty);
        },
      );

      test(
        'fromJson allows null cursor',
        () {
          final json = <String, dynamic>{
            'cursor': null,
            'images': [],
          };

          final response = ProgressGalleryResponse.fromJson(json);

          expect(response.cursor, isNull);
          expect(response.images, isEmpty);
        },
      );
    },
  );
}

extension on int {
  Future<void> get milliseconds {
    return Future.delayed(Duration(milliseconds: this));
  }
}
