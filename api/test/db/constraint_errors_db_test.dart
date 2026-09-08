@Tags(['db'])
library;

import 'package:heart/db/db.dart';
import 'package:heart/models/errors.dart';
import 'package:postgres/postgres.dart' hide Connection;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Covers `apiExceptionForDbError` — the mapping `apiHandler` consults before
/// falling through to a 500 (heart-api#74).
///
/// Deliberately driven by **real** Postgres errors rather than fabricated ones:
/// `ServerException`'s constructor is private, and more importantly the mapping
/// keys on constraint *names*, so a hand-written fake would happily agree with
/// a name the schema does not actually use. Each case provokes the violation
/// against the live schema and feeds the driver's own exception to the mapper.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String userId;

  setUpAll(() async {
    await h.setupDatabase();
    userId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  /// Runs [sql], expecting it to fail, and returns whatever the mapper makes of
  /// the driver's exception.
  Future<ApiException?> mapped(String sql, [Map<String, dynamic> params = const {}]) async {
    try {
      await h.exec(sql, params);
    } on ServerException catch (e) {
      return apiExceptionForDbError(e);
    }
    fail('expected $sql to raise a ServerException');
  }

  // A well-formed uuid that is not any exercise — the shape the app actually
  // sent in the incident.
  const ghostExercise = '01a07dfe-0bf2-7d18-a1fa-79abe2a92472';

  group('foreign key violations become refusals', () {
    test('exercise_preferences.exercise_id → 404 unknown_exercise', () async {
      final result = await mapped(
        'INSERT INTO exercise_preferences (user_id, exercise_id, unit_system) '
        'VALUES (@u, @e::uuid, @s)',
        {'u': userId, 'e': ghostExercise, 's': 'metric'},
      );

      expect(result, isA<NotFound>());
      expect(result?.code, 'unknown_exercise');
      expect(result?.statusCode, 404);
    });

    test('goals.exercise_id → 404 unknown_exercise', () async {
      // Goals reach the same FK from a different route, and never wrapped it —
      // proof the mapping is generic rather than a patch on one endpoint.
      final result = await mapped(
        'INSERT INTO goals (user_id, metric, exercise_id, stages) '
        "VALUES (@u, 'topSetWeight', @e::uuid, '[{\"target\": 100}]'::jsonb)",
        {'u': userId, 'e': ghostExercise},
      );

      expect(result?.code, 'unknown_exercise');
      expect(result?.statusCode, 404);
    });

    test('workout_exercises.exercise_id → 404 unknown_exercise', () async {
      final workoutId = await h.seedWorkout(userId: userId);

      final result = await mapped(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) '
        'VALUES (@w::uuid, @e::uuid, 0)',
        {'w': workoutId, 'e': ghostExercise},
      );

      expect(result?.code, 'unknown_exercise');
    });

    test('a foreign key nobody mapped still refuses with a 400, never a 500', () async {
      // The default is what keeps this closed: a foreign key added later must
      // not silently reopen the hole.
      final result = await mapped(
        'INSERT INTO comments (author_id, body, workout_id) VALUES (@a, @b, @w::uuid)',
        {'a': 'itest-no-such-profile', 'b': 'orphan', 'w': ghostExercise},
      );

      expect(result, isA<BadRequest>());
      expect(result?.code, 'invalid_reference');
      expect(result?.statusCode, 400);
    });
  });

  group('other error classes', () {
    test('an unclaimed unique violation → 400 duplicate', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.exec(
        'INSERT INTO exercise_preferences (user_id, exercise_id, unit_system) VALUES (@u, @e::uuid, @s)',
        {'u': userId, 'e': exerciseId, 's': 'metric'},
      );

      final result = await mapped(
        'INSERT INTO exercise_preferences (user_id, exercise_id, unit_system) VALUES (@u, @e::uuid, @s)',
        {'u': userId, 'e': exerciseId, 's': 'imperial'},
      );

      expect(result?.code, 'duplicate');
      expect(result?.statusCode, 400);
    });

    test('a genuine fault is left alone, so it still reaches the 500', () async {
      // Only the client-caused classes are downgraded; laundering a real bug
      // into a 4xx would hide it.
      final result = await mapped('SELECT * FROM no_such_table_here');

      expect(result, isNull);
    });

    test('a non-database error is not claimed', () {
      expect(apiExceptionForDbError(StateError('boom')), isNull);
    });
  });
}

class _Harness extends DatabaseTestBase;
