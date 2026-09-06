@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ApiTemplateService` query strings against a
/// live Postgres: template CRUD, plus the sharing flow reworked for cursor
/// pagination (idempotent share create, `limit + 1` list keyed on the share id,
/// delete-by-uuid).
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String coachId; // owns templates; shares to student
  late String studentId;
  late String strangerId;
  late String listOwnerId; // isolated, for getTemplates pagination

  TemplateRequest tReq(String userId, String name, {int order = 0, String? id}) =>
      TemplateRequest(userId: userId, name: name, order: order, id: id);

  /// Number of `templates` rows for [id] — used to confirm a replayed create
  /// did not insert a second row.
  Future<int> templateRowCount(String id) async {
    final rows = await h.exec('SELECT count(*) AS n FROM templates WHERE id = @id::uuid', {'id': id});
    return rows.first.toColumnMap()['n'] as int;
  }

  /// A coach-owned master template with one exercise + set, ready to share.
  Future<String> seedMasterTemplate() async {
    final templateId = await h.insertId(
      'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
      {'u': coachId, 'n': h.uniqueName('Master')},
    );
    final exerciseId = await h.seedGlobalExercise();
    final teId = await h.insertId(
      'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) VALUES (@t, @e, 0) RETURNING id',
      {'t': templateId, 'e': exerciseId},
    );
    await h.exec(
      'INSERT INTO template_exercise_sets (template_exercise_id, weight, reps, set_order) VALUES (@te, 100, 5, 0)',
      {'te': teId},
    );
    return templateId;
  }

  setUpAll(() async {
    await h.setupDatabase();
    coachId = await h.seedProfile();
    studentId = await h.seedProfile();
    strangerId = await h.seedProfile();
    listOwnerId = await h.seedProfile();
    await h.seedConnection(initiator: coachId, target: studentId, role: 'COACH');
  });

  tearDownAll(h.teardownDatabase);

  group('template CRUD', () {
    test('createTemplate persists and getTemplate reads it back', () async {
      final (created, isNew) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, 'Leg day'));
      expect(created.name, 'Leg day');
      expect(isNew, isTrue);

      final fetched = await h.db.getTemplate(userId: coachId, templateId: created.id);
      expect(fetched.id, created.id);
      expect(fetched.name, 'Leg day');
    });

    test('getTemplate is owner-scoped (NotFound for another user)', () async {
      final (created, _) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, 'Private'));
      await expectLater(
        h.db.getTemplate(userId: strangerId, templateId: created.id),
        throwsA(isA<NotFound>()),
      );
    });

    test('getTemplates walks the owner\'s arrangement with limit+1 pagination', () async {
      // Deliberately out of creation order: the third one created sits first.
      final (t1, _) = await h.db.createTemplateOrExisting(userId: listOwnerId, body: tReq(listOwnerId, 'T1', order: 1));
      final (t2, _) = await h.db.createTemplateOrExisting(userId: listOwnerId, body: tReq(listOwnerId, 'T2', order: 2));
      final (t0, _) = await h.db.createTemplateOrExisting(userId: listOwnerId, body: tReq(listOwnerId, 'T0', order: 0));

      final page1 = await h.db.getTemplates(userId: listOwnerId, limit: 1);
      expect(page1.items, hasLength(1));
      expect(page1.hasMore, isTrue);
      expect(page1.items.single.id, t0.id, reason: 'order_index wins over creation order');

      OrderedCursor after(Template t) => OrderedCursor(order: t.order, id: t.id);

      final page2 = await h.db.getTemplates(userId: listOwnerId, cursor: after(page1.items.single), limit: 1);
      expect(page2.items.single.id, t1.id);
      expect(page2.hasMore, isTrue);

      final page3 = await h.db.getTemplates(userId: listOwnerId, cursor: after(page2.items.single), limit: 1);
      expect(page3.items.single.id, t2.id);
      expect(page3.hasMore, isFalse);
    });

    test('templates sharing an order_index page by id without repeating or skipping', () async {
      final owner = await h.seedProfile();
      final created = [
        for (var i = 0; i < 5; i++)
          (await h.db.createTemplateOrExisting(userId: owner, body: tReq(owner, 'Tied $i'))).$1,
      ];

      final walked = <String>[];
      OrderedCursor? cursor;
      do {
        final page = await h.db.getTemplates(userId: owner, cursor: cursor, limit: 2);
        walked.addAll(page.items.map((t) => t.id));
        cursor = page.hasMore ? OrderedCursor(order: page.items.last.order, id: page.items.last.id) : null;
      } while (cursor != null);

      // All at order 0, so the id tie-break has to carry the whole walk.
      expect(walked, created.map((t) => t.id).toList());
    });

    test('updateTemplate renames an owned template', () async {
      final (created, _) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, 'Before'));
      final updated = await h.db.updateTemplate(userId: coachId, templateId: created.id, body: tReq(coachId, 'After'));
      expect(updated.id, created.id);
      expect(updated.name, 'After');
    });

    test('updateTemplate on a template you do not own throws NotFound', () async {
      final (created, _) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, 'Mine'));
      await expectLater(
        h.db.updateTemplate(userId: strangerId, templateId: created.id, body: tReq(strangerId, 'Yours')),
        throwsA(isA<NotFound>()),
      );
    });

    test('deleteTemplate removes an owned template', () async {
      final (created, _) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, 'Temp'));
      await h.db.deleteTemplate(coachId: coachId, templateId: created.id);
      await expectLater(
        h.db.getTemplate(userId: coachId, templateId: created.id),
        throwsA(isA<NotFound>()),
      );
    });
  });

  // heart-api#66: anonymous-account upsync replay. Templates have no
  // natural key (two may share a name — see the regression test below), so a
  // client-minted id owned by the caller is the only thing a retry can land
  // on; unlike exercises/workouts/goals there is no name-match fallback.
  group('idempotent create (heart-api#66)', () {
    test('reposting the same client id is idempotent: first creates, second is a no-op', () async {
      const id = '019def00-0000-7000-8000-00000000a001';
      final name = h.uniqueName('Idempotent');

      final (first, firstCreated) = await h.db.createTemplateOrExisting(
        userId: coachId,
        body: tReq(coachId, name, id: id),
      );
      expect(firstCreated, isTrue);
      expect(first.id, id);

      // Same id, different payload — the replay is ignored wholesale, not
      // merged; the original row comes back untouched.
      final (second, secondCreated) = await h.db.createTemplateOrExisting(
        userId: coachId,
        body: tReq(coachId, h.uniqueName('ShouldBeIgnored'), id: id),
      );
      expect(secondCreated, isFalse);
      expect(second.id, id);
      expect(second.name, name);

      expect(await templateRowCount(id), 1);
    });

    test('two templates may share a name — templates have no natural key', () async {
      final name = h.uniqueName('SameName');
      final (a, aCreated) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, name));
      final (b, bCreated) = await h.db.createTemplateOrExisting(userId: coachId, body: tReq(coachId, name));

      expect(aCreated, isTrue);
      expect(bCreated, isTrue);
      expect(a.id, isNot(b.id));
    });

    test('an id already owned by a different user is Forbidden with id_taken', () async {
      const id = '019def00-0000-7000-8000-00000000a002';
      await h.db.createTemplateOrExisting(
        userId: coachId,
        body: tReq(coachId, h.uniqueName('Theirs'), id: id),
      );

      await expectLater(
        h.db.createTemplateOrExisting(
          userId: strangerId,
          body: tReq(strangerId, h.uniqueName('AttemptedTake'), id: id),
        ),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    // Regression: the foreign-id check and the folder-ownership guard are two
    // independent conditions on the same INSERT guard; if a bad folderId
    // alone were allowed to block the insert, a hostile id_taken attempt that
    // also happened to name a folder it didn't own would never trip the pkey
    // violation, and would see a misleading 404 instead. The foreign id must win.
    test('a foreign id with an invalid folderId is still id_taken, not folder NotFound', () async {
      const id = '019def00-0000-7000-8000-00000000a003';
      await h.db.createTemplateOrExisting(
        userId: coachId,
        body: tReq(coachId, h.uniqueName('Theirs'), id: id),
      );

      await expectLater(
        h.db.createTemplateOrExisting(
          userId: strangerId,
          body: TemplateRequest(
            userId: strangerId,
            id: id,
            name: h.uniqueName('AttemptedTake'),
            folderId: '00000000-0000-7000-8000-000000000000', // owned by no one
          ),
        ),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });
  });

  group('template shares', () {
    test('shareTemplate returns the share uuid and is idempotent', () async {
      final master = await seedMasterTemplate();

      final first = await h.db.shareTemplate(coachId: coachId, targetUserId: studentId, masterTemplateId: master);
      expect(first.id, isNotEmpty);
      expect(first.id, contains('-')); // a uuid, not the old composite

      // Second call hits the `_existing` branch — COALESCE must surface ex.id.
      final again = await h.db.shareTemplate(coachId: coachId, targetUserId: studentId, masterTemplateId: master);
      expect(again.id, equals(first.id));
    });

    test('getTemplateShares paginates with limit+1 and walks by share id', () async {
      // A fresh coach so the share list is isolated from other cases.
      final coach = await h.seedProfile();
      final student = await h.seedProfile();
      await h.seedConnection(initiator: coach, target: student, role: 'COACH');
      final mA = await h.insertId(
        'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
        {'u': coach, 'n': h.uniqueName('MA')},
      );
      final mB = await h.insertId(
        'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
        {'u': coach, 'n': h.uniqueName('MB')},
      );

      await h.db.shareTemplate(coachId: coach, targetUserId: student, masterTemplateId: mA);
      final shareB = await h.db.shareTemplate(coachId: coach, targetUserId: student, masterTemplateId: mB);

      final firstPage = await h.db.getTemplateShares(userId: coach, limit: 1);
      expect(firstPage.items, hasLength(1));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.items.single.id, equals(shareB.id)); // newest first

      final secondPage = await h.db.getTemplateShares(userId: coach, cursor: firstPage.items.single.id, limit: 1);
      expect(secondPage.items, hasLength(1));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.items.single.id, isNot(equals(shareB.id)));
    });

    test('copying an exercise into the student library carries its movement over', () async {
      // A fresh pair so the student's library starts without the exercise and
      // the share is forced down the _copied_exercises branch.
      final coach = await h.seedProfile();
      final student = await h.seedProfile();
      await h.seedConnection(initiator: coach, target: student, role: 'COACH');

      // Coach-owned, not global: a global would resolve by name for the student
      // and never reach the _copied_exercises INSERT this test is about.
      final name = h.uniqueName('Movement');
      final exerciseId = await h.insertId(
        'INSERT INTO exercises (name, category, target, user_id, movement) '
        'VALUES (@n, @c, @t, @u, @m::jsonb) RETURNING id',
        {
          'n': name,
          'c': 'Barbell',
          't': 'Legs',
          'u': coach,
          'm':
              '{"groups": ["squat_bilateral"], "axialLoad": "high", "stability": "free", '
              '"unilateral": false, "impact": "none", "skill": "moderate"}',
        },
      );

      final templateId = await h.insertId(
        'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
        {'u': coach, 'n': h.uniqueName('MovementMaster')},
      );
      await h.exec(
        'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) VALUES (@t, @e, 0)',
        {'t': templateId, 'e': exerciseId},
      );

      await h.db.shareTemplate(coachId: coach, targetUserId: student, masterTemplateId: templateId);

      // The student's copy must keep the substitution data, or a shared
      // exercise silently loses the ability to offer swaps.
      final rows = await h.db.getExercises(student);
      final copy = (rows['exercises'] as List).cast<Map<String, dynamic>>().firstWhere(
        (e) => e['name'] == name && e['own'] == true,
      );
      expect((copy['movement'] as Map)['groups'], ['squat_bilateral']);
      expect((copy['movement'] as Map)['axialLoad'], 'high');

      // Unlike the other cases here, this one leaves user-owned exercises behind
      // that template_exercises references under a RESTRICT FK. Drop the
      // templates first or the shared teardown cannot cascade the profiles.
      await h.exec('DELETE FROM templates WHERE user_id = ANY(@ids)', {
        'ids': [coach, student],
      });
    });

    test('shareTemplate reports the master it came from', () async {
      final master = await seedMasterTemplate();
      final share = await h.db.shareTemplate(coachId: coachId, targetUserId: studentId, masterTemplateId: master);
      expect(share.masterTemplateId, master);
    });

    // The permission gate used to check only that a connection row existed, so
    // anyone who had ever sent a request — or been blocked — could push
    // templates into the other person's library.
    for (final status in ['pending', 'declined', 'severed', 'blocked', 'paused']) {
      test('a $status connection is not permission to assign', () async {
        final coach = await h.seedProfile();
        final student = await h.seedProfile();
        await h.seedConnection(initiator: coach, target: student, role: 'COACH', status: status);
        final master = await h.insertId(
          'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
          {'u': coach, 'n': h.uniqueName('Gated')},
        );

        await expectLater(
          h.db.shareTemplate(coachId: coach, targetUserId: student, masterTemplateId: master),
          throwsA(isA<Forbidden>()),
        );
      });
    }

    test('deleteShare removes the share by its uuid', () async {
      final master = await seedMasterTemplate();
      final share = await h.db.shareTemplate(coachId: coachId, targetUserId: studentId, masterTemplateId: master);

      await h.db.deleteShare(coachId: coachId, shareId: share.id);

      final after = await h.db.getTemplateShares(userId: coachId, limit: 50);
      expect(after.items.map((s) => s.id), isNot(contains(share.id)));
    });
  });
}

class _Harness extends DatabaseTestBase;
