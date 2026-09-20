part of 'inputs.dart';

/// The account PUT is a discriminated union on `action`; a body without a
/// recognized action is a profile upsert.
sealed class AccountUpsertIn {
  const new();

  static Future<AccountUpsertIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['action']) {
      'scheduleAccountDeletion' => ScheduleAccountDeletionIn._(appleGrant: ScheduleAccountDeletionIn._grant(json)),
      'undoAccountDeletion' => const UndoAccountDeletionIn(),
      'removeAvatar' => const RemoveAvatarIn(),
      'uploadAvatar' => UploadAvatarIn._(mimeType: json.imageMimeType(req.config.allowedMimeTypes)),
      _ => ProfileUpsertIn._(user: User.fromJson(json)),
    };
  }
}

/// Schedules the account for deletion — the mirror of [UndoAccountDeletionIn],
/// and in the same union for that reason.
///
/// The deletion is a scheduled one, so this is a write to the profile rather
/// than a removal of it; `DELETE` would have said otherwise, and could not have
/// carried [appleGrant] without a request body the spec discourages.
class ScheduleAccountDeletionIn extends AccountUpsertIn {
  /// Absent for Google and password accounts, which have no Apple grant to
  /// revoke. Absent is not a failure — the deletion proceeds either way.
  final AppleDeletionGrant? appleGrant;

  const new _({this.appleGrant});

  /// Half a grant is a refusal: a code with no client cannot be exchanged, and
  /// dropping it silently would leave the app listed under the user's Apple ID
  /// with nothing to show for it.
  static AppleDeletionGrant? _grant(Map<String, dynamic> json) {
    return switch ((json['appleAuthorizationCode'], json['appleClientId'])) {
      (null, null) => null,
      (final String code, final String clientId) when code.isNotEmpty && clientId.isNotEmpty => AppleDeletionGrant(
        authorizationCode: code,
        clientId: clientId,
      ),
      _ => throw const BadRequest(
        reason: 'appleAuthorizationCode and appleClientId are given together or not at all',
        code: 'incomplete_apple_grant',
      ),
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
