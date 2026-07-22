@Tags(['db'])
library;

import 'package:postgres/postgres.dart' hide Connection;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Exercises the real template-share query strings against a live Postgres,
/// covering the parts reworked for cursor pagination: share creation (incl. the
/// idempotent `COALESCE(ns.id, ex.id)` path), `limit + 1` list pagination keyed
/// on the share id, and delete-by-uuid.
///
/// Tagged `db` — skipped by the default `dart test` run (see `dart_test.yaml`),
/// which has no database. Run explicitly against a local `heart` DB with:
///   dart test --run-skipped -t db
void main() {
  final harness = _Harness();

  // Unique per run so repeated local runs don't collide on the UNIQUE
  // (coach_id, master_template_id, student_id) constraint.
  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final coachId = 'itest-coach-$suffix';
  final studentId = 'itest-student-$suffix';
  late String masterA;
  late String masterB;
  final createdExercises = <String>[];

  Future<void> exec(String sql, [Map<String, dynamic> params = const {}]) async {
    await harness.pool.execute(Sql.named(sql), parameters: params);
  }

  Future<String> seedMasterTemplate(String name) async {
    final rows = await harness.pool.execute(
      Sql.named('INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id'),
      parameters: {'u': coachId, 'n': name},
    );
    final templateId = rows.first.toColumnMap()['id'].toString();

    final exRows = await harness.pool.execute(
      Sql.named('INSERT INTO exercises (name, category, target) VALUES (@n, @c, @t) RETURNING id'),
      parameters: {'n': 'ITest Ex $name $suffix', 'c': 'Barbell', 't': 'Chest'},
    );
    final exerciseId = exRows.first.toColumnMap()['id'].toString();
    createdExercises.add(exerciseId);

    final teRows = await harness.pool.execute(
      Sql.named(
        'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) '
        'VALUES (@t, @e, 0) RETURNING id',
      ),
      parameters: {'t': templateId, 'e': exerciseId},
    );
    final teId = teRows.first.toColumnMap()['id'].toString();

    await exec(
      'INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, set_order) '
      'VALUES (@te, 100, 5, 0)',
      {'te': teId},
    );
    return templateId;
  }

  setUpAll(() async {
    await harness.setupDatabase();
    await exec('INSERT INTO profiles (id, username, email) VALUES (@id, @u, @e)', {
      'id': coachId,
      'u': 'coach_$suffix',
      'e': 'coach_$suffix@test.local',
    });
    await exec('INSERT INTO profiles (id, username, email) VALUES (@id, @u, @e)', {
      'id': studentId,
      'u': 'student_$suffix',
      'e': 'student_$suffix@test.local',
    });
    await exec(
      'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status) '
      "VALUES (@c, @s, 'COACH', 'ATHLETE', 'fitness', 'active')",
      {'c': coachId, 's': studentId},
    );
    masterA = await seedMasterTemplate('Master A');
    masterB = await seedMasterTemplate('Master B');
  });

  tearDownAll(() async {
    // profiles cascade to templates/shares/connections/copied exercises.
    await exec('DELETE FROM profiles WHERE id = ANY(@ids)', {
      'ids': [coachId, studentId],
    });
    // Global master exercises (user_id NULL) have no owner to cascade from.
    for (final id in createdExercises) {
      await exec('DELETE FROM exercises WHERE id = @id::uuid', {'id': id});
    }
    await harness.teardownDatabase();
  });

  test('shareTemplate returns the share uuid and is idempotent', () async {
    final first = await harness.db.shareTemplate(
      coachId: coachId,
      targetUserId: studentId,
      masterTemplateId: masterA,
    );
    expect(first.id, isNotEmpty);
    expect(first.id, contains('-')); // looks like a uuid, not the old composite

    // Second call hits the `_existing` branch — COALESCE must surface ex.id.
    final again = await harness.db.shareTemplate(
      coachId: coachId,
      targetUserId: studentId,
      masterTemplateId: masterA,
    );
    expect(again.id, equals(first.id));
  });

  test('getTemplateShares paginates with limit+1 and walks by share id', () async {
    // masterA already shared above; add masterB so the coach has two shares.
    final shareB = await harness.db.shareTemplate(
      coachId: coachId,
      targetUserId: studentId,
      masterTemplateId: masterB,
    );

    final firstPage = await harness.db.getTemplateShares(userId: coachId, limit: 1);
    expect(firstPage.items, hasLength(1));
    expect(firstPage.hasMore, isTrue);
    // uuidv7 ids sort chronologically; the newer share (B) comes first.
    expect(firstPage.items.single.id, equals(shareB.id));

    final secondPage = await harness.db.getTemplateShares(
      userId: coachId,
      cursor: firstPage.items.single.id,
      limit: 1,
    );
    expect(secondPage.items, hasLength(1));
    expect(secondPage.hasMore, isFalse);
    expect(secondPage.items.single.id, isNot(equals(shareB.id)));
  });

  test('deleteShare removes the share by its uuid', () async {
    final before = await harness.db.getTemplateShares(userId: coachId, limit: 50);
    final target = before.items.first;

    await harness.db.deleteShare(coachId: coachId, shareId: target.id);

    final after = await harness.db.getTemplateShares(userId: coachId, limit: 50);
    expect(after.items.map((s) => s.id), isNot(contains(target.id)));
    expect(after.items, hasLength(before.items.length - 1));
  });
}

class _Harness extends DatabaseTestBase {}
