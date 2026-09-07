import 'package:heart_models/heart_models.dart';

abstract interface class ApiProfileService {
  Future<User> upsertProfile(User user);

  Future<void> scheduleAccountDeletion({
    required String userId,
    String? scheduleArn,
    DateTime? scheduledAt,
  });

  Future<User> undoAccountDeletion({required String userId});

  Future<User> updateAvatarUrl({required String userId, String? avatarUrl});

  Future<void> deleteAccount({required String userId});

  /// Per-collection row counts for everything [userId] owns — what a data
  /// export has to carry, so the app can check its local mirror against it.
  ///
  /// API-only, like [ApiExercisePreferenceService]: the app implements no
  /// server-side counting, so this has no place on a shared interface.
  Future<AccountSummary> getAccountSummary(String userId);
}
