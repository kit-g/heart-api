import 'package:heart_models/heart_models.dart';

/// Days the user chose not to train (heart-api#202). API-side, like
/// [ProgramService]: the app keeps skips in its own local database.
abstract interface class SkipService {
  /// The user's skips, newest first.
  Future<Page<TrainingSkip>> getSkips({required String userId, String? cursor, int limit = 30});

  /// Idempotent on the skip's id.
  Future<(TrainingSkip, bool created)> createSkip({required String userId, required TrainingSkip skip});

  /// Deleting what isn't there is not an error.
  Future<void> deleteSkip({required String userId, required String skipId});
}
