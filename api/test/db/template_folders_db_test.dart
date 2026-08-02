@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of `ApiTemplateFolderService` and the folder half of
/// `ApiTemplateService` against a live Postgres: folder CRUD and its uniqueness
/// rules, filing templates in and out, the `ON DELETE SET NULL (folder_id)`
/// behaviour, and folder-wide assignment.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String strangerId;

  TemplateRequest tReq(String userId, String name, {Object? folderId = _absent}) {
    return TemplateRequest(
      userId: userId,
      name: name,
      folderId: folderId == _absent ? null : folderId as String?,
      movesFolder: folderId != _absent,
    );
  }

  Future<TemplateFolder> newFolder(String userId, String prefix) {
    return h.db.createFolder(
      userId: userId,
      folder: TemplateFolder(name: h.uniqueName(prefix)),
    );
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    strangerId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('folder CRUD', () {
    test('createFolder persists and getFolders reads it back', () async {
      final user = await h.seedProfile();
      final created = await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Push', order: 2),
      );

      expect(created.id, isNotEmpty);
      expect(created.name, 'Push');
      expect(created.order, 2);
      expect(created.templateCount, 0);

      final folders = await h.db.getFolders(userId: user);
      expect(folders.map((f) => f.name), ['Push']);
    });

    test('getFolders counts the templates filed in each folder', () async {
      final user = await h.seedProfile();
      final push = await newFolder(user, 'Push');
      final pull = await newFolder(user, 'Pull');

      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Bench', folderId: push.id),
      );
      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Dips', folderId: push.id),
      );
      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Rows', folderId: pull.id),
      );
      await h.db.createTemplate(userId: user, body: tReq(user, 'Unfiled'));

      final counts = {for (final f in await h.db.getFolders(userId: user)) f.id: f.templateCount};
      expect(counts[push.id], 2);
      expect(counts[pull.id], 1);
    });

    test('getFolders is owner-scoped', () async {
      await newFolder(ownerId, 'Private');
      final theirs = await h.db.getFolders(userId: strangerId);
      expect(theirs.map((f) => f.id), isNot(contains(ownerId)));
      expect(theirs.every((f) => f.templateCount != null), isTrue, reason: 'the list query always counts');
    });

    test('getFolders orders by order_index then name', () async {
      final user = await h.seedProfile();
      await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Zebra', order: 0),
      );
      await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Alpha', order: 0),
      );
      await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'First', order: -1),
      );

      final names = (await h.db.getFolders(userId: user)).map((f) => f.name).toList();
      expect(names, ['First', 'Alpha', 'Zebra']);
    });

    test('a duplicate folder name is rejected regardless of case', () async {
      final user = await h.seedProfile();
      await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Legs'),
      );

      await expectLater(
        h.db.createFolder(
          userId: user,
          folder: TemplateFolder(name: 'legs'),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('two users may each have a folder of the same name', () async {
      final a = await h.seedProfile();
      final b = await h.seedProfile();
      await h.db.createFolder(
        userId: a,
        folder: TemplateFolder(name: 'Shared Name'),
      );

      final theirs = await h.db.createFolder(
        userId: b,
        folder: TemplateFolder(name: 'Shared Name'),
      );
      expect(theirs.name, 'Shared Name');
    });

    test('updateFolder renames and reorders', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Before');

      final updated = await h.db.updateFolder(
        userId: user,
        folderId: folder.id!,
        folder: TemplateFolder(name: 'After', order: 5),
      );

      expect(updated.id, folder.id);
      expect(updated.name, 'After');
      expect(updated.order, 5);
    });

    test('updateFolder keeps the template count', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Counted');
      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'One', folderId: folder.id),
      );

      final updated = await h.db.updateFolder(
        userId: user,
        folderId: folder.id!,
        folder: TemplateFolder(name: h.uniqueName('Renamed')),
      );
      expect(updated.templateCount, 1);
    });

    test('updateFolder rejects a rename onto another folder of the same user', () async {
      final user = await h.seedProfile();
      final taken = await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Taken'),
      );
      final folder = await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: 'Free'),
      );

      await expectLater(
        h.db.updateFolder(
          userId: user,
          folderId: folder.id!,
          folder: TemplateFolder(name: taken.name),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('updateFolder allows a folder to keep its own name', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Same');

      final updated = await h.db.updateFolder(
        userId: user,
        folderId: folder.id!,
        folder: TemplateFolder(name: folder.name, order: 3),
      );
      expect(updated.order, 3);
    });

    test('updateFolder on a folder you do not own throws NotFound', () async {
      final folder = await newFolder(ownerId, 'NotYours');

      await expectLater(
        h.db.updateFolder(
          userId: strangerId,
          folderId: folder.id!,
          folder: TemplateFolder(name: 'Mine now'),
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('deleteFolder removes it and unfiles its templates rather than deleting them', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Doomed');
      final template = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Survivor', folderId: folder.id),
      );

      await h.db.deleteFolder(userId: user, folderId: folder.id!);

      expect((await h.db.getFolders(userId: user)).map((f) => f.id), isNot(contains(folder.id)));
      final survivor = await h.db.getTemplate(userId: user, templateId: template.id);
      expect(survivor.folderId, isNull);
    });

    test('deleteFolder on a folder you do not own throws NotFound', () async {
      final folder = await newFolder(ownerId, 'Guarded');
      await expectLater(
        h.db.deleteFolder(userId: strangerId, folderId: folder.id!),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('filing templates', () {
    test('createTemplate files into a folder', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Filed');

      final created = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'In folder', folderId: folder.id),
      );
      expect(created.folderId, folder.id);
    });

    // The nested folder is what saves the client a second request, so every read
    // path has to carry it — a join that returns the id but not the name would
    // still satisfy every `folderId` assertion in this file.
    test('every read nests the whole folder, not just its id', () async {
      final user = await h.seedProfile();
      final folder = await h.db.createFolder(
        userId: user,
        folder: TemplateFolder(name: h.uniqueName('Nested'), order: 4),
      );

      final created = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Filed', folderId: folder.id),
      );
      final fetched = await h.db.getTemplate(userId: user, templateId: created.id);
      final listed = (await h.db.getTemplates(userId: user, limit: 50)).items.single;
      final updated = await h.db.updateTemplate(
        userId: user,
        templateId: created.id,
        body: tReq(user, 'Renamed', folderId: folder.id),
      );

      for (final (label, template) in [
        ('create', created),
        ('get', fetched),
        ('list', listed),
        ('update', updated),
      ]) {
        expect(template.folder?.name, folder.name, reason: '$label lost the folder name');
        expect(template.folder?.order, 4, reason: '$label lost the folder order');
        expect(
          template.folder?.templateCount,
          isNull,
          reason: '$label invented a count; only the folder list counts',
        );
      }
    });

    test('an unfiled template nests no folder at all', () async {
      final user = await h.seedProfile();
      final created = await h.db.createTemplate(userId: user, body: tReq(user, 'Loose'));

      expect(created.folder, isNull);
      expect(created.toMap().containsKey('folder'), isFalse);
    });

    test('createTemplate with no folderId leaves the template unfiled', () async {
      final user = await h.seedProfile();
      final created = await h.db.createTemplate(userId: user, body: tReq(user, 'Loose'));
      expect(created.folderId, isNull);
    });

    test('createTemplate into another user\'s folder throws NotFound', () async {
      final folder = await newFolder(ownerId, 'Theirs');

      await expectLater(
        h.db.createTemplate(
          userId: strangerId,
          body: tReq(strangerId, 'Sneaky', folderId: folder.id),
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('updateTemplate moves a template between folders', () async {
      final user = await h.seedProfile();
      final from = await newFolder(user, 'From');
      final to = await newFolder(user, 'To');
      final created = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Mover', folderId: from.id),
      );

      final moved = await h.db.updateTemplate(
        userId: user,
        templateId: created.id,
        body: tReq(user, 'Mover', folderId: to.id),
      );
      expect(moved.folderId, to.id);
    });

    test('updateTemplate with an explicit null folderId unfiles the template', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Temporary');
      final created = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Evictee', folderId: folder.id),
      );

      final updated = await h.db.updateTemplate(
        userId: user,
        templateId: created.id,
        body: tReq(user, 'Evictee', folderId: null),
      );
      expect(updated.folderId, isNull);
    });

    test('updateTemplate without a folderId key leaves the filing alone', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Sticky');
      final created = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Stayer', folderId: folder.id),
      );

      final updated = await h.db.updateTemplate(
        userId: user,
        templateId: created.id,
        body: tReq(user, 'Renamed only'),
      );
      expect(updated.name, 'Renamed only');
      expect(updated.folderId, folder.id);
    });

    test('updateTemplate into another user\'s folder throws NotFound', () async {
      final theirs = await newFolder(ownerId, 'Fortress');
      final mine = await h.db.createTemplate(userId: strangerId, body: tReq(strangerId, 'Mine'));

      await expectLater(
        h.db.updateTemplate(
          userId: strangerId,
          templateId: mine.id,
          body: tReq(strangerId, 'Mine', folderId: theirs.id),
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('getTemplates filters to one folder', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Only');
      final inside = await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Inside', folderId: folder.id),
      );
      await h.db.createTemplate(userId: user, body: tReq(user, 'Outside'));

      final page = await h.db.getTemplates(userId: user, folderId: folder.id, limit: 50);
      expect(page.items.map((t) => t.id), [inside.id]);
    });

    test('getTemplates lists only the unfiled ones on request', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Hidden');
      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Filed', folderId: folder.id),
      );
      final loose = await h.db.createTemplate(userId: user, body: tReq(user, 'Loose'));

      final page = await h.db.getTemplates(userId: user, unfiledOnly: true, limit: 50);
      expect(page.items.map((t) => t.id), [loose.id]);
    });

    test('getTemplates with no filter returns filed and unfiled alike', () async {
      final user = await h.seedProfile();
      final folder = await newFolder(user, 'Mixed');
      await h.db.createTemplate(
        userId: user,
        body: tReq(user, 'Filed', folderId: folder.id),
      );
      await h.db.createTemplate(userId: user, body: tReq(user, 'Loose'));

      final page = await h.db.getTemplates(userId: user, limit: 50);
      expect(page.items, hasLength(2));
    });
  });

  group('folder assignment', () {
    late String coachId;
    late String studentId;
    late TemplateFolder folder;

    setUp(() async {
      coachId = await h.seedProfile();
      studentId = await h.seedProfile();
      await h.seedConnection(initiator: coachId, target: studentId, role: 'COACH');
      folder = await newFolder(coachId, 'Block');
    });

    /// A coach-owned template in [folder], built on a *global* exercise so the
    /// student resolves it by name instead of getting a copy — that path is
    /// covered in `templates_db_test.dart` and would complicate teardown here.
    Future<Template> seedFiledTemplate(String name) async {
      final exercise = await h.seedGlobalExercise();
      final exerciseName = await h.exec('SELECT name FROM exercises WHERE id = @id::uuid', {'id': exercise});
      return h.db.createTemplate(
        userId: coachId,
        body: TemplateRequest(
          userId: coachId,
          name: name,
          folderId: folder.id,
          movesFolder: true,
          exercises: [
            TemplateExerciseRequest(
              exerciseName: exerciseName.first.toColumnMap()['name'] as String,
              order: 0,
              sets: const [TemplateSetRequest(weight: 60, reps: 5)],
            ),
          ],
        ),
      );
    }

    test('shareFolder assigns every template in the folder', () async {
      final a = await seedFiledTemplate('A');
      final b = await seedFiledTemplate('B');

      final shares = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);

      expect(shares, hasLength(2));
      expect(shares.map((s) => s.masterTemplateId).toSet(), {a.id, b.id});
      expect(shares.every((s) => s.assignedTo.id == studentId), isTrue);
    });

    test('shareFolder ignores templates outside the folder', () async {
      await seedFiledTemplate('Inside');
      await h.db.createTemplate(userId: coachId, body: tReq(coachId, 'Outside'));

      final shares = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      expect(shares, hasLength(1));
    });

    test('the student copies carry the exercises and sets over, unfiled', () async {
      await seedFiledTemplate('Full');

      final shares = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      final copy = await h.db.getTemplate(userId: studentId, templateId: shares.first.studentTemplateId);

      expect(copy.folderId, isNull, reason: 'the coach\'s filing is not the student\'s');
      expect(copy.length, 1);
      expect(copy.first.length, 1);
      expect(copy.first.first.weight, 60);
    });

    test('the student copy records who assigned it', () async {
      await seedFiledTemplate('Attributed');

      final shares = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      final copy = await h.db.getTemplate(userId: studentId, templateId: shares.first.studentTemplateId);

      expect(copy.isAssigned, isTrue);
      expect(copy.assignedBy?.id, coachId);
      expect(copy.syncEnabled, isTrue);
    });

    test('re-assigning a folder is idempotent per template', () async {
      await seedFiledTemplate('First');

      final first = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      final again = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);

      expect(again.map((s) => s.id), first.map((s) => s.id));
    });

    test('a template added after the first assignment goes on the next one', () async {
      await seedFiledTemplate('Original');
      final first = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      expect(first, hasLength(1));

      final added = await seedFiledTemplate('Added later');
      final second = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);

      expect(second, hasLength(2));
      expect(second.map((s) => s.masterTemplateId), contains(added.id));
      // The original's share is the same row, not a duplicate.
      expect(second.map((s) => s.id).toSet(), containsAll(first.map((s) => s.id)));
    });

    test('assigning an empty folder is a no-op, not an error', () async {
      final shares = await h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: folder.id!);
      expect(shares, isEmpty);
    });

    test('assigning a folder that is not yours throws NotFound', () async {
      final theirs = await newFolder(strangerId, 'Elsewhere');
      await expectLater(
        h.db.shareFolder(coachId: coachId, targetUserId: studentId, folderId: theirs.id!),
        throwsA(isA<NotFound>()),
      );
    });

    test('assigning to an unknown user throws NotFound', () async {
      await expectLater(
        h.db.shareFolder(coachId: coachId, targetUserId: 'nobody-at-all', folderId: folder.id!),
        throwsA(isA<NotFound>()),
      );
    });

    test('assigning to someone you are not connected to is forbidden', () async {
      await seedFiledTemplate('Blocked');
      final outsider = await h.seedProfile();

      await expectLater(
        h.db.shareFolder(coachId: coachId, targetUserId: outsider, folderId: folder.id!),
        throwsA(isA<Forbidden>()),
      );
    });
  });
}

/// Sentinel for "the request body had no `folderId` key at all", which is
/// distinct from `folderId: null`.
const _absent = Object();

class _Harness extends DatabaseTestBase {}
