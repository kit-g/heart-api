import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'mocks.mocks.dart';

void main() {
  group('Workout.copy', () {
    const bench = {
      'id': '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6',
      'name': 'Bench Press',
      'category': 'Barbell',
      'target': 'Chest',
    };
    final workout = Workout.fromJson({
      'id': 'w-1',
      'name': 'Push',
      'start': '2026-10-05T10:00:00Z',
      'end': '2026-10-05T11:00:00Z',
      'exercises': [
        {
          'id': 'we-1',
          'order': 0,
          'exercise': bench,
          'start': '2026-10-05T10:00:00Z',
          'met': 6.0,
          'note': 'pause at the bottom',
          'sets': [
            {
              'id': 's-1',
              'reps': 5,
              'weight': 100,
              'started_at': '2026-10-05T10:00:00Z',
              'completed': true,
              'completed_at': '2026-10-05T10:01:00Z',
              'set_type': 'warmup',
              'rpe': 6,
            },
          ],
        },
      ],
    });

    test('a same-id copy is the session as it is', () {
      final same = workout.copy(sameId: true);
      expect(same.toMap(), workout.toMap());
      expect(same.single.id, 'we-1');
      expect(same.single.met, 6.0);
      final set = same.single.single;
      expect(set.id, 's-1');
      expect(set.isCompleted, isTrue);
      expect(set.completedAt, DateTime.parse('2026-10-05T10:01:00Z'));
      expect(set.rpe, 6.0);
      expect(set.setType, SetType.warmup);
    });

    test('a same-id copy owns its sets', () {
      final same = workout.copy(sameId: true);
      same.single.single.isCompleted = false;
      expect(workout.single.single.isCompleted, isTrue);
    });

    test('a repeat mints new ids and starts incomplete and unrated', () {
      final repeat = workout.copy();
      expect(repeat.id, isNot('w-1'));
      expect(repeat.single.id, isNot('we-1'));
      expect(repeat.single.met, isNull);
      expect(repeat.single.note, 'pause at the bottom');
      final set = repeat.single.single;
      expect(set.id, isNot('s-1'));
      expect(set.isCompleted, isFalse);
      expect(set.completedAt, isNull);
      expect(set.rpe, isNull);
      expect(set.setType, SetType.warmup);
      expect(set.reps, 5);
    });
  });

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
                'id': weightedSet.id,
                'completed': false,
                'started_at': startTime.toIso8601String(),
                'reps': 8,
                'weight': 100.0,
                'set_type': 'normal',
                'rpe': null,
              },
            ),
          );
        },
      );

      test(
        'a new set gets a v7 uuid id, not its start timestamp',
        () {
          final startTime = DateTime.parse('2025-01-21T12:00:00Z');
          final one = ExerciseSet(mockExercise, start: startTime);
          final two = ExerciseSet(mockExercise, start: startTime);

          expect(one.id, isNot(equals(startTime.toIso8601String())));
          expect(timestampOfUuidV7(one.id), isNotNull);
          // Firebase-era ids were the start timestamp, so two sets sharing a
          // start collided unless callers staggered starts by a few ms.
          expect(one.id, isNot(equals(two.id)));
          expect(one, isNot(equals(two)));
        },
      );

      test(
        'toMap emits completed_at once the set is ticked',
        () {
          final startTime = DateTime.parse('2025-01-21T12:00:00Z');
          final completedTime = DateTime.parse('2025-01-21T12:01:30Z');
          final set = ExerciseSet(mockExercise, reps: 8, weight: 100.0, start: startTime)
            ..isCompleted = true
            ..completedAt = completedTime;

          final map = set.toMap();

          expect(map['completed'], isTrue);
          expect(map['completed_at'], equals(completedTime.toIso8601String()));
        },
      );

      test(
        'fromJson restores completed_at',
        () {
          final set = ExerciseSet.fromJson(mockExercise, {
            'id': '2025-01-21T12:00:00.000Z',
            'started_at': '2025-01-21T12:00:00Z',
            'completed_at': '2025-01-21T12:01:30Z',
            'completed': true,
            'reps': 8,
            'weight': 100.0,
          });

          expect(set.completedAt, equals(DateTime.parse('2025-01-21T12:01:30Z')));
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

      test(
        'fromJson scrubs legacy zero-valued measurements a weight set cannot have',
        () {
          // The shape an old serializer wrote into device DBs — see
          // https://github.com/kit-g/heart-api/issues/51
          final set = ExerciseSet.fromJson(mockExercise, {
            'id': '2025-07-18T18:57:25.878943Z',
            'completed': true,
            'reps': 12,
            'duration': 0,
            'distance': 0.0,
            'weight': 60.0,
          });

          expect(set.reps, equals(12));
          expect(set.weight, equals(60.0));
          expect(set.duration, isNull);
          expect(set.distance, isNull);

          final map = set.toMap();
          expect(map, isNot(contains('duration')));
          expect(map, isNot(contains('distance')));

          final row = set.toRow();
          expect(row, isNot(contains('duration')));
          expect(row, isNot(contains('distance')));
        },
      );

      test(
        'a cardio set keeps duration and distance but drops weight and reps',
        () {
          final cardio = MockExercise();
          when(cardio.name).thenReturn('Running');
          when(cardio.category).thenReturn(Category.cardio);
          when(cardio.target).thenReturn(Target.cardio);

          final set = ExerciseSet.fromJson(cardio, {
            'id': 'set-uuid',
            'started_at': '2025-01-21T12:00:00Z',
            'reps': 12,
            'weight': 60.0,
            'duration': 300,
            'distance': 1.5,
          });

          expect(set.duration, equals(300));
          expect(set.distance, equals(1.5));
          expect(set.weight, isNull);
          expect(set.reps, isNull);
        },
      );

      test(
        'a weighted distance set keeps weight and distance, ranked by their product',
        () {
          final carry = MockExercise();
          when(carry.category).thenReturn(Category.weightedDistance);

          final set = ExerciseSet(carry, reps: 3, weight: 40.0, duration: 45, distance: 0.05);
          expect(set.weight, equals(40.0));
          expect(set.distance, equals(0.05));
          expect(set.reps, isNull);
          expect(set.duration, isNull);
          expect(set.total, closeTo(2.0, 1e-9));
          expect(set.canBeCompleted, isTrue);

          expect(ExerciseSet(carry, weight: 40.0).canBeCompleted, isFalse);
          expect(ExerciseSet(carry, weight: 40.0).total, isNull);
          expect(ExerciseSet(carry, weight: 60.0, distance: 0.05) > set, isTrue);
        },
      );

      test(
        'a weighted duration set keeps weight and duration, ranked by their product',
        () {
          final hold = MockExercise();
          when(hold.category).thenReturn(Category.weightedDuration);

          final set = ExerciseSet(hold, reps: 3, weight: 20.0, duration: 60, distance: 1.0);
          expect(set.weight, equals(20.0));
          expect(set.duration, equals(60));
          expect(set.reps, isNull);
          expect(set.distance, isNull);
          expect(set.total, equals(1200.0));
          expect(set.canBeCompleted, isTrue);

          expect(ExerciseSet(hold, duration: 60).canBeCompleted, isFalse);
          set.setMeasurements(duration: 90, reps: 5);
          expect(set.duration, equals(90));
          expect(set.reps, isNull);
        },
      );

      test(
        'the factory drops measurements outside the category',
        () {
          final set = ExerciseSet(
            mockExercise,
            reps: 10,
            weight: 50.0,
            duration: 120,
            distance: 2.0,
          );

          expect(set.reps, equals(10));
          expect(set.weight, equals(50.0));
          expect(set.duration, isNull);
          expect(set.distance, isNull);
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
          expect(((map['sets'] as List).first as Map)['id'], starterSet.id);
        },
      );

      test(
        'toMap carries a note and omits it when unset',
        () {
          when(mockExercise.toMap()).thenReturn({'name': 'Mock Exercise'});

          final withNote = WorkoutExercise(starter: starterSet)..note = 'do one hand at a time';
          expect(withNote.toMap()['note'], 'do one hand at a time');

          final without = WorkoutExercise(starter: starterSet);
          expect(without.toMap().containsKey('note'), isFalse);
        },
      );

      test(
        'fromJson restores the note',
        () {
          final exercise = Exercise(
            name: 'Bench',
            category: Category.weightedBodyWeight,
            target: Target.chest,
          );
          final parsed = WorkoutExercise.fromJson({
            'id': 'we-1',
            'exercise': exercise.toMap(),
            'exercise_order': 0,
            'note': 'pause at the bottom',
            'sets': <Map>[],
          });

          expect(parsed.note, 'pause at the bottom');
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
        'copy carries the exercise note forward',
        () {
          workoutExercise.note = 'do one hand at a time';
          workout.append(workoutExercise);

          final copy = workout.copy();

          expect(copy.first.note, 'do one hand at a time');
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
                  'id': '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6',
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

      group(
        'synced flag',
        () {
          test(
            'a locally created workout starts unsynced',
            () {
              expect(Workout(name: 'Fresh').synced, isFalse);
              expect(Workout.fromExercises([workoutExercise], name: 'Fresh').synced, isFalse);
            },
          );

          test(
            'a workout read from a server row is synced',
            () {
              final workout = Workout.fromRow(
                {
                  'id': 'workout-row',
                  'name': 'Server Workout',
                  'started_at': '2025-01-21T12:00:00Z',
                  'completed_at': '2025-01-21T13:00:00Z',
                  'exercises': [],
                },
                imageUrl: (key) => 'https://example.com/$key',
              );

              expect(workout.synced, isTrue);
            },
          );

          test(
            'fromJson treats an absent synced field as synced (server response)',
            () {
              final workout = Workout.fromJson({
                'id': 'workout-123',
                'name': 'Server Workout',
                'start': '2025-01-21T12:00:00Z',
              });

              expect(workout.synced, isTrue);
            },
          );

          test(
            'fromJson maps the int form (0/1) of local rows',
            () {
              Workout fromSynced(Object? value) => Workout.fromJson({
                'id': 'workout-123',
                'name': 'Local Workout',
                'start': '2025-01-21T12:00:00Z',
                'synced': value,
              });

              expect(fromSynced(1).synced, isTrue);
              expect(fromSynced(0).synced, isFalse);
              expect(fromSynced(true).synced, isTrue);
              expect(fromSynced(false).synced, isFalse);
            },
          );
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

      test(
        'timestamp is recovered from either era of workout id',
        () {
          WorkoutImage imageFor(String workoutId) {
            return WorkoutImage.fromJson({
              'workoutId': workoutId,
              'id': 'photo-1',
              'url': 'https://example.com/image.jpg',
              'key': 'image.jpg',
            });
          }

          // Firebase-era workout ids were start timestamps.
          expect(
            imageFor('2025-01-21T12:00:00.000Z').timestamp,
            equals(DateTime.parse('2025-01-21T12:00:00.000Z')),
          );

          // Today's are v7 uuids, which embed their mint instant.
          final before = DateTime.timestamp();
          final minted = imageFor(uuidV7()).timestamp;
          final after = DateTime.timestamp();
          expect(minted, isNotNull);
          expect(minted!.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
          expect(minted.isAfter(after.add(const Duration(seconds: 1))), isFalse);

          // An id from neither era yields nothing.
          expect(imageFor('not-an-id').timestamp, isNull);
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

  group(
    'set type, RPE and the workout note',
    () {
      const benchPress = {
        'id': '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6',
        'name': 'Bench Press',
        'category': 'Barbell',
        'target': 'Chest',
      };

      Map<String, dynamic> row({Object? note, List<Map<String, dynamic>> sets = const []}) => {
        'id': 'workout-row',
        'name': 'Server Workout',
        'started_at': '2025-01-21T12:00:00Z',
        'completed_at': '2025-01-21T13:00:00Z',
        'note': note,
        'exercises': [
          {'id': 'we-1', 'exercise': benchPress, 'exercise_order': 0, 'sets': sets},
        ],
      };

      Workout read({Object? note, List<Map<String, dynamic>> sets = const []}) => Workout.fromRow(
        row(note: note, sets: sets),
        imageUrl: (key) => key,
      );

      test('SetType reads every wire word, and absent or null as normal', () {
        for (final type in SetType.values) {
          expect(SetType.fromString(type.value), type);
        }
        expect(SetType.fromString(null), SetType.normal);
        expect(() => SetType.fromString('rest-pause'), throwsArgumentError);
      });

      test('a read never fails on a type newer than this build: it is a normal set', () {
        expect(SetType.lenient('rest-pause'), SetType.normal);
        expect(SetType.lenient('drop'), SetType.drop);
        final workout = read(
          sets: [
            {'id': 's1', 'reps': 5, 'weight': 100, 'set_type': 'rest-pause'},
          ],
        );
        expect(workout.first.first.setType, SetType.normal);
      });

      test('a set reads its type and RPE off the server row', () {
        final workout = read(
          sets: [
            {'id': 's1', 'reps': 5, 'weight': 100, 'set_type': 'warmup', 'rpe': null},
            {'id': 's2', 'reps': 5, 'weight': 140, 'set_type': 'failure', 'rpe': 9.5},
            {'id': 's3', 'reps': 5, 'weight': 120, 'rpe': 8},
          ],
        );
        final sets = workout.first.toList();

        expect(sets.map((s) => s.setType), [SetType.warmup, SetType.failure, SetType.normal]);
        expect(sets.map((s) => s.rpe), [null, 9.5, 8.0]);
      });

      test('a set always writes both fields, null RPE included, so they can be cleared', () {
        final set = ExerciseSet(mockExercise, reps: 5, weight: 100, setType: .drop, rpe: 7.5);
        expect(set.toMap(), containsPair('set_type', 'drop'));
        expect(set.toMap(), containsPair('rpe', 7.5));

        set
          ..setType = .normal
          ..rpe = null;
        expect(set.toMap(), containsPair('set_type', 'normal'));
        expect(set.toMap(), containsPair('rpe', null));
      });

      test('RPE and set type are kept on a set of any category', () {
        when(mockExercise.category).thenReturn(Category.cardio);
        final set = ExerciseSet(mockExercise, duration: 600, distance: 2, setType: .warmup, rpe: 4);
        expect(set.setType, SetType.warmup);
        expect(set.rpe, 4.0);
      });

      test('a set copy keeps the type and starts unrated', () {
        final set = ExerciseSet(mockExercise, reps: 5, weight: 100, setType: .warmup, rpe: 6);
        final copy = set.copy();
        expect(copy.setType, SetType.warmup);
        expect(copy.rpe, isNull);
      });

      test('warm-ups count toward neither the best set nor the volume', () {
        final exercise = WorkoutExercise(
          starter: ExerciseSet(mockExercise, reps: 10, weight: 200, setType: .warmup),
        )..add(ExerciseSet(mockExercise, reps: 5, weight: 100));

        expect(exercise.best?.weight, 100.0);
        expect(exercise.total, 500.0);
      });

      test('drop and failure sets count like working sets', () {
        final exercise =
            WorkoutExercise(
                starter: ExerciseSet(mockExercise, reps: 5, weight: 100),
              )
              ..add(ExerciseSet(mockExercise, reps: 10, weight: 80, setType: .drop))
              ..add(ExerciseSet(mockExercise, reps: 2, weight: 150, setType: .failure));

        expect(exercise.total, 500.0 + 800.0 + 300.0);
        expect(exercise.best?.setType, SetType.drop);
      });

      test('an exercise of only warm-ups has no best set and no volume', () {
        final exercise = WorkoutExercise(
          starter: ExerciseSet(mockExercise, reps: 10, weight: 40, setType: .warmup),
        );
        expect(exercise.best, isNull);
        expect(exercise.total, 0);
      });

      test('the workout note reads off the row and the local JSON', () {
        expect(read(note: 'felt strong').note, 'felt strong');
        expect(read().note, isNull);

        final local = Workout.fromJson({
          'id': 'workout-123',
          'start': '2025-01-21T12:00:00Z',
          'note': 'deload week',
        });
        expect(local.note, 'deload week');
      });

      test('the workout note is always written, null included, so it can be cleared', () {
        final workout = Workout(name: 'Push')..note = 'short on time';
        expect(workout.toMap(), containsPair('note', 'short on time'));

        workout.note = null;
        expect(workout.toMap(), containsPair('note', null));
      });

      test('the same session keeps its note and RPEs; a repeat starts without them', () {
        final workout = read(
          note: 'felt strong',
          sets: [
            {'id': 's1', 'reps': 5, 'weight': 100, 'set_type': 'warmup', 'rpe': 6},
          ],
        );

        final same = workout.copy(sameId: true);
        expect(same.note, 'felt strong');
        expect(same.first.first.rpe, 6.0);
        expect(same.first.first.setType, SetType.warmup);

        final repeat = workout.copy();
        expect(repeat.note, isNull);
        expect(repeat.first.first.rpe, isNull);
        expect(repeat.first.first.setType, SetType.warmup);
      });

      test('a workout that round-trips through toMap and fromJson keeps it all', () {
        final workout = read(
          note: 'We’re',
          sets: [
            {'id': 's1', 'reps': 5, 'weight': 100, 'set_type': 'drop', 'rpe': 6.5},
          ],
        );
        final back = Workout.fromJson(workout.toMap());

        expect(back.note, 'We’re');
        expect(back.first.first.setType, SetType.drop);
        expect(back.first.first.rpe, 6.5);
      });
    },
  );

  group(
    'pauses',
    () {
      Map<String, dynamic> row({Object? pauses = const []}) => {
        'id': 'workout-row',
        'name': 'Server Workout',
        'started_at': '2026-10-03T18:00:00Z',
        'completed_at': '2026-10-03T19:00:00Z',
        'exercises': const [],
        'pauses': ?pauses,
      };

      Workout read({Object? pauses = const []}) => Workout.fromRow(row(pauses: pauses), imageUrl: (key) => key);

      const pauses = [
        {'start': '2026-10-03T18:02:11Z', 'end': '2026-10-03T18:09:40Z'},
        {'start': '2026-10-03T18:30:00Z', 'end': '2026-10-03T18:35:00Z'},
      ];

      test('read off the row and the local JSON, absent as none', () {
        final workout = read(pauses: pauses);
        expect(workout.pauses, hasLength(2));
        expect(workout.pauses.first.start, DateTime.utc(2026, 10, 3, 18, 2, 11));
        expect(workout.pauses.first.duration, const Duration(minutes: 7, seconds: 29));
        expect(read(pauses: null).pauses, isEmpty);
        expect(Workout.fromJson({'id': 'w', 'start': '2026-10-03T18:00:00Z'}).pauses, isEmpty);
      });

      test('duration leaves paused time out; start and end stay as they were', () {
        final workout = read(pauses: pauses);
        expect(workout.duration, const Duration(hours: 1) - const Duration(minutes: 12, seconds: 29));
        expect(workout.start, DateTime.utc(2026, 10, 3, 18));
        expect(workout.end, DateTime.utc(2026, 10, 3, 19));
        expect(read().duration, const Duration(hours: 1));
      });

      test('elapsed leaves closed pauses out', () {
        final start = DateTime.now().subtract(const Duration(minutes: 30));
        final workout = Workout.fromJson({'id': 'w', 'start': start.toIso8601String()})
          ..pauses = [WorkoutPause(start: start, end: start.add(const Duration(minutes: 10)))];
        expect(workout.elapsed().inMinutes, 20);
      });

      test('always written, empty included, and round-trips', () {
        expect(Workout(name: 'Push').toMap(), containsPair('pauses', isEmpty));
        final workout = read(pauses: pauses);
        expect(workout.toMap()['pauses'], [
          {'start': '2026-10-03T18:02:11.000Z', 'end': '2026-10-03T18:09:40.000Z'},
          {'start': '2026-10-03T18:30:00.000Z', 'end': '2026-10-03T18:35:00.000Z'},
        ]);
        final back = Workout.fromJson(workout.toMap());
        expect(back.duration, workout.duration);
      });

      test('the same session keeps its pauses; a repeat starts without them', () {
        final workout = read(pauses: pauses);
        final same = workout.copy(sameId: true);
        expect(same.pauses, hasLength(2));
        same.pauses.clear();
        expect(workout.pauses, hasLength(2), reason: 'a copy owns its list');
        expect(workout.copy().pauses, isEmpty);
      });
    },
  );
}

extension on int {
  Future<void> get milliseconds {
    return Future.delayed(Duration(milliseconds: this));
  }
}
