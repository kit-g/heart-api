part of 'inputs.dart';

/// The account PUT is a discriminated union on `action`; a body without a
/// recognized action is a profile upsert.
sealed class AccountUpsertIn {
  const new();

  static Future<AccountUpsertIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['action']) {
      'undoAccountDeletion' => const UndoAccountDeletionIn(),
      'removeAvatar' => const RemoveAvatarIn(),
      'uploadAvatar' => UploadAvatarIn._(mimeType: json.imageMimeType(req.config.allowedMimeTypes)),
      _ => ProfileUpsertIn._(user: User.fromJson(json)),
    };
  }
}

class UndoAccountDeletionIn extends AccountUpsertIn {
  const new();
}

class RemoveAvatarIn extends AccountUpsertIn {
  const new();
}

class UploadAvatarIn extends AccountUpsertIn {
  final String mimeType;

  const new _({required this.mimeType});
}

class ProfileUpsertIn extends AccountUpsertIn {
  final User user;

  const new _({required this.user});
}

/// The optional Apple half of a deletion request.
///
/// `DELETE /accounts` was bodiless before Apple grants and still is for Google
/// and password accounts, so a request without a JSON body is a deletion with
/// no grant rather than a malformed one. Half a grant is neither: a code with
/// no client cannot be exchanged, and silently dropping it would leave the app
/// listed under the user's Apple ID with nothing to show for it.
class AccountDeleteIn {
  final AppleDeletionGrant? appleGrant;

  const new _({this.appleGrant});

  static Future<AccountDeleteIn> fromRequest(Request req) async {
    final json = switch (req.body.bodyType?.mimeType) {
      MimeType.json => await req.json(),
      _ => const <String, dynamic>{},
    };

    return AccountDeleteIn._(
      appleGrant: switch ((json['appleAuthorizationCode'], json['appleClientId'])) {
        (null, null) => null,
        (final String code, final String clientId) when code.isNotEmpty && clientId.isNotEmpty => AppleDeletionGrant(
          authorizationCode: code,
          clientId: clientId,
        ),
        _ => throw const BadRequest(
          reason: 'appleAuthorizationCode and appleClientId are given together or not at all',
          code: 'incomplete_apple_grant',
        ),
      },
    );
  }
}
