@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ApiProfileService` query strings against a
/// live Postgres: account upsert/get, schedule/undo/delete of account deletion,
/// and avatar updates — plus the NotFound and no-op branches the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  /// Upserts a fresh profile through the service, tracking it for cascade
  /// cleanup (it's created via the service, not [seedProfile]).
  Future<User> upsertNew(User user) async {
    h.trackProfile(user.id);
    return h.db.upsertProfile(user);
  }

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  group('upsertProfile', () {
    test('inserts a new profile and returns the persisted user', () async {
      final id = h.uid('user');
      final user = User(
        id: id,
        email: '$id@test.local',
        displayName: 'Original Name',
        avatar: 'https://cdn.test/a.png',
        settings: const Settings(themeMode: 'dark', accentColor: '#ff0000'),
      );

      final saved = await upsertNew(user);

      expect(saved.id, id);
      expect(saved.email, '$id@test.local');
      expect(saved.displayName, 'Original Name');
      expect(saved.remoteAvatar, 'https://cdn.test/a.png');
      expect(saved.settings.themeMode, 'dark');
      expect(saved.settings.accentColor, '#ff0000');
      expect(saved.scheduledForDeletionAt, isNull);
    });

    test('upserting the same id updates in place rather than duplicating', () async {
      final id = h.uid('user');
      await upsertNew(User(id: id, email: '$id@test.local', displayName: 'First'));

      final updated = await h.db.upsertProfile(
        User(
          id: id,
          email: 'changed-$id@test.local',
          displayName: 'Second',
          avatar: 'https://cdn.test/new.png',
          settings: const Settings(themeMode: 'light'),
        ),
      );

      // The row reflects the second write...
      expect(updated.displayName, 'Second');
      expect(updated.email, 'changed-$id@test.local');
      expect(updated.remoteAvatar, 'https://cdn.test/new.png');
      expect(updated.settings.themeMode, 'light');

      // ...and there is still exactly one row for this id.
      final rows = await h.exec('SELECT id FROM profiles WHERE id = @id', {'id': id});
      expect(rows, hasLength(1));
    });
  });

  group('scheduleAccountDeletion', () {
    test('sets the schedule ARN and scheduled timestamp', () async {
      final id = await upsertNew(
        User(id: h.uid('user'), email: 'x@test.local', displayName: 'Sched'),
      ).then((u) => u.id);
      final when = DateTime.utc(2026, 8, 1, 12);

      await h.db.scheduleAccountDeletion(userId: id, scheduleArn: 'arn:aws:scheduler:del-$id', scheduledAt: when);

      final row = (await h.exec(
        'SELECT account_deletion_schedule, scheduled_for_deletion_at FROM profiles WHERE id = @id',
        {'id': id},
      )).first.toColumnMap();
      expect(row['account_deletion_schedule'], 'arn:aws:scheduler:del-$id');
      expect((row['scheduled_for_deletion_at'] as DateTime).toUtc(), when);
    });

    test('null arguments coalesce to the existing values (no clobbering)', () async {
      final id = await upsertNew(
        User(id: h.uid('user'), email: 'x@test.local', displayName: 'Sched'),
      ).then((u) => u.id);
      final when = DateTime.utc(2026, 8, 2, 9);
      await h.db.scheduleAccountDeletion(userId: id, scheduleArn: 'arn:keep-$id', scheduledAt: when);

      // A second call with nulls must leave the previously-set values intact.
      await h.db.scheduleAccountDeletion(userId: id);

      final row = (await h.exec(
        'SELECT account_deletion_schedule, scheduled_for_deletion_at FROM profiles WHERE id = @id',
        {'id': id},
      )).first.toColumnMap();
      expect(row['account_deletion_schedule'], 'arn:keep-$id');
      expect((row['scheduled_for_deletion_at'] as DateTime).toUtc(), when);
    });

    test('is a no-op for an unknown user id', () async {
      // UPDATE ... WHERE id = @userId matches nothing; the method returns void
      // and must not throw.
      await expectLater(
        h.db.scheduleAccountDeletion(userId: h.uid('ghost'), scheduleArn: 'arn:none'),
        completes,
      );
    });
  });

  group('undoAccountDeletion', () {
    test('clears the schedule fields and returns the user', () async {
      final id = await upsertNew(User(id: h.uid('user'), email: 'x@test.local', displayName: 'Undo')).then((u) => u.id);
      await h.db.scheduleAccountDeletion(
        userId: id,
        scheduleArn: 'arn:undo-$id',
        scheduledAt: DateTime.utc(2026, 8, 3, 10),
      );

      final restored = await h.db.undoAccountDeletion(userId: id);

      expect(restored.id, id);
      expect(restored.scheduledForDeletionAt, isNull);

      final row = (await h.exec(
        'SELECT account_deletion_schedule, scheduled_for_deletion_at FROM profiles WHERE id = @id',
        {'id': id},
      )).first.toColumnMap();
      expect(row['account_deletion_schedule'], isNull);
      expect(row['scheduled_for_deletion_at'], isNull);
    });

    test('throws NotFound when the user does not exist', () async {
      await expectLater(
        h.db.undoAccountDeletion(userId: h.uid('ghost')),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('updateAvatarUrl', () {
    test('updates the avatar and returns the user', () async {
      final id = await upsertNew(
        User(id: h.uid('user'), email: 'x@test.local', displayName: 'Avatar', avatar: 'https://cdn.test/old.png'),
      ).then((u) => u.id);

      final updated = await h.db.updateAvatarUrl(userId: id, avatarUrl: 'https://cdn.test/updated.png');

      expect(updated.id, id);
      expect(updated.remoteAvatar, 'https://cdn.test/updated.png');
    });

    test('clears the avatar when passed null', () async {
      final id = await upsertNew(
        User(id: h.uid('user'), email: 'x@test.local', displayName: 'Avatar', avatar: 'https://cdn.test/old.png'),
      ).then((u) => u.id);

      final updated = await h.db.updateAvatarUrl(userId: id, avatarUrl: null);

      expect(updated.remoteAvatar, isNull);
    });

    test('throws NotFound when the user does not exist', () async {
      await expectLater(
        h.db.updateAvatarUrl(userId: h.uid('ghost'), avatarUrl: 'https://cdn.test/x.png'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('deleteAccount', () {
    test('removes the profile row', () async {
      // Seeded via the harness so cleanup is a harmless no-op after this delete.
      final id = await h.seedProfile();

      await h.db.deleteAccount(userId: id);

      final rows = await h.exec('SELECT id FROM profiles WHERE id = @id', {'id': id});
      expect(rows, isEmpty);
    });

    test('is a no-op for an unknown user id', () async {
      await expectLater(h.db.deleteAccount(userId: h.uid('ghost')), completes);
    });
  });
}

class _Harness extends DatabaseTestBase;
