import '../models/auth.dart';
import '../models/misc.dart';

abstract interface class AccountService implements HeaderAuthenticatedService, FileUploadService {
  Future<User> registerAccount(User user);

  Future<String?> undoAccountDeletion();

  Future<String?> deleteAccount({required String accountId});

  Future<({String url, Map<String, String> fields})?> getAvatarUploadLink(String userId, {String? imageMimeType});

  Future<bool> removeAvatar(String userId);
}
