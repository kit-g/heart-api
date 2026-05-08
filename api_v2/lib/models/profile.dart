import 'package:heart_models/heart_models.dart';

abstract interface class ApiProfileService {
  Future<User> upsertProfile(User user);

  Future<void> scheduleAccountDeletion({
    required String userId,
    String? scheduleArn,
    DateTime? scheduledAt,
  });

  Future<User> undoAccountDeletion({required String userId});

  Future<void> deleteAccount({required String userId});
}
