import 'package:heart/globals/config.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  group('AccountUpsertIn — discriminated union on action', () {
    late MockAppConfig config;

    setUp(() {
      config = MockAppConfig();
      when(config.allowedMimeTypes).thenReturn(const {'image/jpeg', 'image/png'});
    });

    Future<AccountUpsertIn> parse(Map<String, dynamic> body) =>
        AccountUpsertIn.fromRequest(jsonRequest(body: body)..config = config);

    test('undoAccountDeletion', () async {
      expect(await parse({'action': 'undoAccountDeletion'}), isA<UndoAccountDeletionIn>());
    });

    test('removeAvatar', () async {
      expect(await parse({'action': 'removeAvatar'}), isA<RemoveAvatarIn>());
    });

    test('uploadAvatar with an allowed mime type', () async {
      final input = await parse({'action': 'uploadAvatar', 'mimeType': 'image/png'});
      expect(input, isA<UploadAvatarIn>());
      expect((input as UploadAvatarIn).mimeType, 'image/png');
    });

    test('uploadAvatar defaults the mime type to image/jpeg', () async {
      final input = await parse({'action': 'uploadAvatar'}) as UploadAvatarIn;
      expect(input.mimeType, 'image/jpeg');
    });

    test('uploadAvatar rejects a mime type outside the allowlist', () async {
      await expectLater(parse({'action': 'uploadAvatar', 'mimeType': 'image/gif'}), throwsA(isA<BadRequest>()));
    });

    test('a body without an action is a profile upsert', () async {
      final input = await parse({'id': 'u1', 'displayName': 'Sam', 'email': 'sam@example.com'});
      expect(input, isA<ProfileUpsertIn>());
      final user = (input as ProfileUpsertIn).user;
      expect(user.id, 'u1');
      expect(user.displayName, 'Sam');
      expect(user.email, 'sam@example.com');
    });

    test('an unrecognized action also falls through to a profile upsert', () async {
      final input = await parse({'action': 'explode', 'id': 'u1'});
      expect(input, isA<ProfileUpsertIn>());
      expect((input as ProfileUpsertIn).user.id, 'u1');
    });
  });
}
