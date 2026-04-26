import 'package:heart_models/heart_models.dart';

abstract interface class ApiProfileService {
  Future<void> upsertProfile(User user);
}
