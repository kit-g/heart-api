import '../models/auth.dart';
import '../models/misc.dart';

abstract interface class AccountService implements HeaderAuthenticatedService, FileUploadService {
  Future<User> registerAccount(User user);

  /// Cancels a scheduled deletion. Throws on failure.
  Future<void> undoAccountDeletion();

  /// Schedules the account for deletion, which can still be undone once this
  /// completes. Throws on failure.
  ///
  /// [appleGrant] is what lets the deletion revoke a Sign in with Apple grant
  /// when it eventually runs; omitted for every other kind of account, and
  /// never a reason for the call to fail.
  Future<void> deleteAccount({required String accountId, AppleDeletionGrant? appleGrant});

  Future<({String url, Map<String, String> fields})?> getAvatarUploadLink(String userId, {String? imageMimeType});

  Future<bool> removeAvatar(String userId);
}
