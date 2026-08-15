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
