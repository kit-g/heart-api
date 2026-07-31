import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/account.dart`, covering the branches that
/// stay within the injected services. The avatar-upload and account-deletion
/// branches construct AWS clients (`Scheduler`) inline and are intentionally
/// left to real-AWS / injection work — not reachable from this rig.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  group('PUT /accounts (profile upsert)', () {
    test('upserts the caller’s own profile', () async {
      when(app.db.upsertProfile(any)).thenAnswer((_) async => User(id: 'u1', displayName: 'Sam'));

      final res = await app.send('PUT', '/accounts', body: {'id': 'u1', 'displayName': 'Sam'});
      expect(res.status, 200);
      verify(app.db.upsertProfile(argThat(isA<User>().having((u) => u.id, 'id', 'u1')))).called(1);
    });

    test('forbids modifying a different user’s profile (403)', () async {
      final res = await app.send('PUT', '/accounts', body: {'id': 'someone-else'});
      expect(res.status, 403);
      verifyNever(app.db.upsertProfile(any));
    });
  });

  group('PUT /accounts (removeAvatar)', () {
    test('deletes the avatar object and clears the stored url', () async {
      when(app.storage.deleteObject(key: anyNamed('key'))).thenAnswer((_) async {});
      when(
        app.db.updateAvatarUrl(userId: anyNamed('userId'), avatarUrl: anyNamed('avatarUrl')),
      ).thenAnswer((_) async => User(id: 'u1'));

      final res = await app.send('PUT', '/accounts', body: {'action': 'removeAvatar'});
      expect(res.status, 200);
      verify(app.storage.deleteObject(key: 'avatars/u1')).called(1);
      verify(app.db.updateAvatarUrl(userId: 'u1', avatarUrl: null)).called(1);
    });
  });
}
