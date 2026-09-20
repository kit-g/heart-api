import 'package:heart/globals/config.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  late MockAppConfig config;

  setUp(() {
    config = MockAppConfig();
    when(config.allowedMimeTypes).thenReturn(const {'image/jpeg', 'image/png'});
  });

  Future<AccountUpsertIn> parse(Map<String, dynamic> body) =>
      AccountUpsertIn.fromRequest(jsonRequest(body: body)..config = config);

  group('AccountUpsertIn — discriminated union on action', () {
    test('scheduleAccountDeletion', () async {
      expect(await parse({'action': 'scheduleAccountDeletion'}), isA<ScheduleAccountDeletionIn>());
    });

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

  group('scheduleAccountDeletion — the optional Apple half', () {
    Future<ScheduleAccountDeletionIn> schedule(Map<String, dynamic> body) async {
      return await parse({'action': 'scheduleAccountDeletion', ...body}) as ScheduleAccountDeletionIn;
    }

    test('carries no grant when none is sent', () async {
      expect((await schedule({})).appleGrant, isNull);
    });

    test('parses a complete grant', () async {
      final input = await schedule({
        'appleAuthorizationCode': 'c0de',
        'appleClientId': 'me.heart-of.ios',
      });

      expect(input.appleGrant?.authorizationCode, 'c0de');
      expect(input.appleGrant?.clientId, 'me.heart-of.ios');
    });

    // Half a grant cannot be exchanged, and dropping it silently would leave
    // the app listed under the user's Apple ID with nothing to show for it.
    for (final (name, body) in [
      ('a code with no client', {'appleAuthorizationCode': 'c0de'}),
      ('a client with no code', {'appleClientId': 'me.heart-of.ios'}),
      ('an empty code', {'appleAuthorizationCode': '', 'appleClientId': 'me.heart-of.ios'}),
      ('a non-string code', {'appleAuthorizationCode': 7, 'appleClientId': 'me.heart-of.ios'}),
    ]) {
      test('$name is a 400', () {
        expect(
          () => schedule(body),
          throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'incomplete_apple_grant')),
        );
      });
    }
  });
}
