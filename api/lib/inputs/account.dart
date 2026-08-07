part of 'inputs.dart';

/// The account PUT is a discriminated union on `action`; a body without a
/// recognized action is a profile upsert.
sealed class AccountUpsertIn {
  const AccountUpsertIn();

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
  const UndoAccountDeletionIn();
}

class RemoveAvatarIn extends AccountUpsertIn {
  const RemoveAvatarIn();
}

class UploadAvatarIn extends AccountUpsertIn {
  final String mimeType;

  const UploadAvatarIn._({required this.mimeType});
}

class ProfileUpsertIn extends AccountUpsertIn {
  final User user;

  const ProfileUpsertIn._({required this.user});
}
