@Tags(['db'])
library;

import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// A library exercise inside a workout or a template is named in the request's
/// locale, as the exercise list names it (heart-api#447); an own exercise keeps
/// the name its owner wrote.
void main() {
  final h = _Harness();

  late String userId;
  late String squat;
  late String own;

  String imageUrl(String key) => key;

  setUpAll(() async {
    await h.setupDatabase();
    userId = await h.seedProfile();
    squat = await h.seedGlobalExercise(name: h.uniqueName('Squat'));
    await h.exec(
      '''
      INSERT INTO exercise_translations (exercise_id, locale, name)
      VALUES (@e::uuid, 'ru', 'Приседания'), (@e::uuid, 'es', 'Sentadilla'), (@e::uuid, 'es_ES', 'Sentadilla ES')
      ''',
      {'e': squat},
    );
    own = await h.insertId(
      'INSERT INTO exercises (name, category, target, user_id) VALUES (@n, @c, @t, @u) RETURNING id',
      {'n': 'Жим Плужниковой', 'c': 'Barbell', 't': 'Chest', 'u': userId},
    );
  });

  tearDownAll(() async {
    // an own exercise can't go while a workout or a template still names it,
    // and the profile's delete would take it first
    await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': userId});
    await h.exec('DELETE FROM templates WHERE user_id = @u', {'u': userId});
    await h.teardownDatabase();
  });

  WorkoutRequest workout() {
    return WorkoutRequest(
      userId: userId,
      body: {
        'name': 'Legs',
        'start': DateTime.utc(2026, 11, 10, 18).toIso8601String(),
        'end': DateTime.utc(2026, 11, 10, 19).toIso8601String(),
        'exercises': [
          for (final (order, exercise) in [squat, own].indexed)
            {
              'exercise': exercise,
              'order': order,
              'sets': [
                {'weight': 100, 'reps': 5, 'completed': true},
              ],
            },
        ],
      },
    );
  }

  List<String> namesOf(Iterable<WorkoutExercise> exercises) => [for (final each in exercises) each.exercise.name];

  group('a workout', () {
    late Workout created;

    setUpAll(() async {
      (created, _) = await h.db.createWorkout(userId: userId, body: workout(), imageUrl: imageUrl, locale: 'ru');
    });

    test('a create answers in the locale', () {
      expect(namesOf(created), ['Приседания', 'Жим Плужниковой']);
    });

    test('a read follows the locale, a regional one falling back to its language', () async {
      Future<List<String>> read(String? locale) async => namesOf(
        await h.db.getWorkout(userId: userId, workoutId: created.id, imageUrl: imageUrl, locale: locale),
      );

      expect(await read('ru'), ['Приседания', 'Жим Плужниковой']);
      expect(await read('es_ES'), ['Sentadilla ES', 'Жим Плужниковой']);
      expect(await read('es_MX'), ['Sentadilla', 'Жим Плужниковой']);
      expect(await read('fr'), [h.nameOf(squat), 'Жим Плужниковой']);
      expect(await read(null), [h.nameOf(squat), 'Жим Плужниковой']);
    });

    test('the list and the owner\'s records do too', () async {
      final page = await h.db.getWorkouts(userId: userId, targetUserId: userId, imageUrl: imageUrl, locale: 'ru');
      expect(namesOf(page.items.single), ['Приседания', 'Жим Плужниковой']);

      final records = await h.db.getRecordSets(userId: userId, exerciseId: squat, locale: 'ru');
      expect(records.single.name, 'Приседания');

      final history = await h.db.getExerciseHistory(userId: userId, exerciseId: squat, locale: 'ru');
      expect(history?.name, 'Приседания');
    });
  });

  test('a template answers and reads in the locale', () async {
    final created = await h.db.createTemplate(
      userId: userId,
      body: TemplateRequest(
        userId: userId,
        name: 'Legs',
        exercises: [
          TemplateExerciseRequest(exerciseId: squat, order: 0, sets: [TemplateSetRequest(weight: 100, reps: 5)]),
          TemplateExerciseRequest(exerciseId: own, order: 1, sets: [TemplateSetRequest(weight: 40, reps: 8)]),
        ],
      ),
      locale: 'ru',
    );
    expect(namesOf(created), ['Приседания', 'Жим Плужниковой']);

    final read = await h.db.getTemplate(userId: userId, templateId: created.id, locale: 'es');
    expect(namesOf(read), ['Sentadilla', 'Жим Плужниковой']);
  });
}

class _Harness extends DatabaseTestBase {
  final _names = <String, String>{};

  @override
  Future<String> seedGlobalExercise({String? name}) async {
    final id = await super.seedGlobalExercise(name: name);
    _names[id] = name!;
    return id;
  }

  /// The library name [id] was seeded with.
  String nameOf(String id) => _names[id]!;
}
