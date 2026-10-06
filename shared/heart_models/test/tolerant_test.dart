import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// Reads from a newer vocabulary than this build knows (heart-api#125): one
/// unknown word never fails the response that carries it, and what this build
/// could not read is carried untouched through its next write.
void main() {
  const benchId = '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6';
  const squatId = '0198c1a2-b3c4-7d5e-8f60-718293a4b5c7';
  const sledId = '0198c1a2-b3c4-7d5e-8f60-718293a4b5c8';
  const bench = <String, Object>{'id': benchId, 'name': 'Bench Press', 'category': 'Barbell', 'target': 'Chest'};
  const squat = <String, Object>{'id': squatId, 'name': 'Squat', 'category': 'Barbell', 'target': 'Legs'};
  // a category this build has never heard of
  const sled = <String, Object>{'id': sledId, 'name': 'Sled Push', 'category': 'Sled', 'target': 'Legs'};

  Map<String, Object> set(String id, {Object reps = 5, num weight = 100, String? type}) {
    return {
      'id': id,
      'reps': reps,
      'weight': weight,
      'started_at': '2026-10-05T10:00:00Z',
      'completed': true,
      'set_type': ?type,
    };
  }

  List<Map> written(Map<String, dynamic> map, String key) => (map[key] as List).cast<Map>();

  group('readEach', () {
    test('keeps what reads and sets the rest aside, in order', () {
      final read = readEach([bench, sled, squat], Exercise.fromJson);
      expect(read.map((e) => e.name), ['Bench Press', 'Squat']);
      expect(read.items, hasLength(2));
      expect(read.unread, [sled]);
    });

    test('a shape this build predates and a malformed value are set aside too', () {
      final read = readEach(
        [
          {
            'id': 'g-1',
            'metric': 'topSetWeight',
            'exerciseId': 'e',
            'stages': [
              {'target': 100},
            ],
          },
          // an unknown word
          {
            'id': 'g-2',
            'metric': 'sleepScore',
            'stages': [
              {'target': 8},
            ],
          },
          // a field of a shape this build does not expect (TypeError)
          {
            'id': 3,
            'metric': 'workouts',
            'cadence': 'week',
            'stages': [
              {'target': 3},
            ],
          },
          // a malformed timestamp (FormatException)
          {
            'id': 'g-4',
            'metric': 'workouts',
            'cadence': 'week',
            'stages': [
              {'target': 3},
            ],
            'createdAt': 'yesterday',
          },
        ],
        Goal.fromJson,
      );
      expect(read.map((goal) => goal.id), ['g-1']);
      expect(read.unread.map((json) => json['id']), ['g-2', 3, 'g-4']);
    });

    test('nothing unknown => everything read, nothing unread', () {
      final read = readEach([bench, squat], Exercise.fromJson);
      expect(read, hasLength(2));
      expect(read.unread, isEmpty);
    });

    test('a bug in the reader is not a vocabulary and propagates', () {
      expect(() => readEach([bench], (_) => throw StateError('bug')), throwsStateError);
    });

    test('an item that is not a JSON object is not a vocabulary either', () {
      expect(() => readEach([bench, 'squat'], Exercise.fromJson), throwsArgumentError);
    });
  });

  group('ExerciseSet with a type this build does not know', () {
    final exercise = Exercise.fromJson(bench);

    test('reads as normal, carries the word, writes it back', () {
      final parsed = ExerciseSet.fromJson(exercise, set('s-1', type: 'cluster'));
      expect(parsed.setType, SetType.normal);
      expect(parsed.setTypeValue, 'cluster');
      expect(parsed.toMap()['set_type'], 'cluster');
      expect(parsed.reps, 5);
    });

    test('a known type is its own value', () {
      expect(ExerciseSet.fromJson(exercise, set('s-1', type: 'warmup')).setTypeValue, 'warmup');
      expect(ExerciseSet.fromJson(exercise, set('s-1')).setTypeValue, 'normal');
      expect(ExerciseSet(exercise, setType: .drop).setTypeValue, 'drop');
    });

    test('assigning a type replaces the word', () {
      final parsed = ExerciseSet.fromJson(exercise, set('s-1', type: 'cluster'))..setType = .drop;
      expect(parsed.setTypeValue, 'drop');
      expect(parsed.toMap()['set_type'], 'drop');
    });

    test('a copy carries the word', () {
      final copy = ExerciseSet.fromJson(exercise, set('s-1', type: 'cluster')).copy();
      expect(copy.setType, SetType.normal);
      expect(copy.setTypeValue, 'cluster');
    });
  });

  group('WorkoutExercise with sets this build cannot read', () {
    final sets = [
      set('s-1'),
      // a shape this build predates
      set('s-2', reps: 'five'),
      set('s-3'),
    ];
    final json = {'id': 'we-1', 'exercise': bench, 'start': '2026-10-05T10:00:00Z', 'sets': sets};

    test('the readable sets are the exercise, the rest is unread', () {
      final parsed = WorkoutExercise.fromJson(json);
      expect(parsed.map((set) => set.id), ['s-1', 's-3']);
      expect(parsed.unread, [sets[1]]);
    });

    test('toMap writes the unread set back where it sat', () {
      final out = written(WorkoutExercise.fromJson(json).toMap(), 'sets');
      expect(out.map((set) => set['id']), ['s-1', 's-2', 's-3']);
      expect(out[1], sets[1]);
    });

    test('an exercise whose every set is unread still names its exercise', () {
      final parsed = WorkoutExercise.fromJson({
        ...json,
        'sets': [sets[1]],
      });
      expect(parsed, isEmpty);
      expect(parsed.unread, hasLength(1));
      final map = parsed.toMap();
      expect(map['exercise'], isNotNull);
      expect(written(map, 'sets').single['id'], 's-2');
    });

    test('an emptied row still names no exercise', () {
      final row = WorkoutExercise(starter: ExerciseSet(Exercise.fromJson(bench)));
      row.remove(row.first);
      expect(row.toMap().containsKey('exercise'), isFalse);
    });
  });

  group('Workout with an exercise this build cannot read', () {
    Map<String, Object> exercise(String id, Map exercise, int order, {List<Map>? sets}) {
      return {
        'id': id,
        'order': order,
        'exercise': exercise,
        'start': '2026-10-05T10:00:00Z',
        'sets': sets ?? [set('$id-s1')],
      };
    }

    final exercises = [
      exercise('we-1', bench, 0),
      exercise('we-2', sled, 1),
      exercise('we-3', squat, 2),
    ];
    final json = {
      'id': 'w-1',
      'name': 'Legs',
      'start': '2026-10-05T10:00:00Z',
      'end': '2026-10-05T11:00:00Z',
      'exercises': exercises,
    };

    test('reads every other exercise; the unknown one is unread, not lost', () {
      final workout = Workout.fromJson(json);
      expect(workout.map((each) => each.exercise.name), ['Bench Press', 'Squat']);
      expect(workout.unread, [exercises[1]]);
      expect(workout.isCompleted, isTrue);
    });

    test('toMap writes it back in place, untouched, with one order sequence', () {
      final out = written(Workout.fromJson(json).toMap(), 'exercises');
      expect(out.map((each) => each['id']), ['we-1', 'we-2', 'we-3']);
      expect(out.map((each) => each['order']), [0, 1, 2]);
      expect(out[1], exercises[1]);
    });

    test('an edit around it keeps it, with orders still unique', () {
      final workout = Workout.fromJson(json);
      workout.remove(workout.first);
      final out = written(workout.toMap(), 'exercises');
      expect(out.map((each) => each['id']), ['we-3', 'we-2']);
      expect(out.map((each) => each['order']), [0, 1]);
      expect(out[1]['exercise'], sled);
    });

    test('fromRow reads the same way', () {
      final workout = Workout.fromRow(
        {'id': 'w-1', 'name': 'Legs', 'started_at': '2026-10-05T10:00:00Z', 'exercises': exercises},
        imageUrl: (key) => key,
      );
      expect(workout, hasLength(2));
      expect(workout.unread, hasLength(1));
    });

    test('a same-id copy carries it; a repeat starts from what this build sees', () {
      final workout = Workout.fromJson(json);
      expect(workout.copy(sameId: true).unread, hasLength(1));
      expect(workout.copy().unread, isEmpty);
    });

    test('a same-id copy carries each exercise\'s unread sets, and an exercise with only those', () {
      final workout = Workout.fromJson({
        ...json,
        'exercises': [
          exercise(
            'we-1',
            bench,
            0,
            sets: [
              set('a'),
              set('b', reps: 'five'),
              set('c'),
            ],
          ),
          exercise('we-2', sled, 1),
          exercise('we-3', squat, 2, sets: [set('x', reps: 'five')]),
        ],
      });
      final same = workout.copy(sameId: true);

      expect(same.map((each) => each.id), ['we-1', 'we-3']);
      expect(same.first.map((set) => set.id), ['a', 'c']);
      expect(same.first.unread, [set('b', reps: 'five')]);
      expect(same.last, isEmpty);
      expect(same.last.unread, hasLength(1));
      expect(same.unread, hasLength(1));
      expect(same.toMap(), workout.toMap(), reason: 'a save of the copy carries what a save of the original would');

      final repeat = workout.copy();
      expect(repeat.map((each) => each.exercise.name), ['Bench Press']);
      expect(repeat.single.unread, isEmpty);
      expect(repeat.unread, isEmpty);
    });

    test('an exercise whose only set is unread survives a save and a tidy', () {
      final workout = Workout.fromJson({
        ...json,
        'exercises': [
          exercise('we-1', bench, 0),
          exercise('we-2', squat, 1, sets: [set('x', reps: 'five')]),
        ],
      });
      expect(workout, hasLength(2));
      expect(workout.last, isEmpty);
      expect(workout.last.unread, hasLength(1));

      workout.removeEmptySets();
      expect(workout, hasLength(2), reason: 'a tidy drops only what is truly empty');

      final out = written(workout.toMap(), 'exercises');
      expect(out.map((each) => each['id']), ['we-1', 'we-2']);
      expect(written(out[1].cast<String, dynamic>(), 'sets').single['id'], 'x');
    });

    test('nothing unknown => nothing unread, same body as before', () {
      final workout = Workout.fromJson({
        ...json,
        'exercises': [exercise('we-1', bench, 0)],
      });
      expect(workout.unread, isEmpty);
      expect(written(workout.toMap(), 'exercises').single['order'], 0);
    });
  });

  group('Template with an exercise this build cannot read', () {
    Map<String, Object> exercise(String id, Map exercise) {
      return {
        'id': id,
        'exercise': exercise,
        'start': '2026-10-05T10:00:00Z',
        'sets': [set('$id-s1')],
      };
    }

    final exercises = [exercise('te-1', sled), exercise('te-2', bench)];
    final json = {'id': 't-1', 'order': 0, 'name': 'Push', 'exercises': exercises};

    test('reads the rest; the unknown one is unread and written back in place', () {
      final template = Template.fromJson(json);
      expect(template.map((each) => each.exercise.name), ['Bench Press']);
      expect(template.unread, [exercises[0]]);

      final out = written(template.toMap(), 'exercises');
      expect(out.map((each) => each['id']), ['te-1', 'te-2']);
      expect(out[0], exercises[0]);
    });

    test('copyWith carries it; toWorkout starts from what this build sees', () {
      final template = Template.fromJson(json);
      expect(template.copyWith(folder: null).unread, hasLength(1));
      expect(template.toWorkout().unread, isEmpty);
      expect(template.toWorkout(), hasLength(1));
    });

    test('fromRow reads the same way', () {
      final template = Template.fromRow({'id': 't-1', 'name': 'Push', 'order_index': 0, 'exercises': exercises});
      expect(template, hasLength(1));
      expect(template.unread, hasLength(1));
    });
  });
}
