import 'package:heart_models/heart_models.dart';

abstract interface class ApiProfileService {
  Future<void> upsertProfile(User user);

  Future<void> scheduleAccountDeletion({
    required String userId,
    required String scheduleArn,
    required DateTime scheduledAt,
  });

  Future<void> undoAccountDeletion({required String userId});

  Future<void> deleteAccount({required String userId});
}
