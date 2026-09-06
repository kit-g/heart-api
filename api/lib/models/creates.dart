/// API-side extensions of the shared service interfaces, for the creates the
/// upsync replay (kit-g/heart-api#66) makes idempotent.
///
/// The shared interfaces in `heart_models` keep their bare-model signatures:
/// the app implements `GoalService` for its local database and consumes the
/// others, so their contracts are app-facing and must stay additive. What the
/// route layer additionally needs — whether the row was minted by this call or
/// already existed — travels through these sub-interfaces instead, the same
/// way `ApiWorkoutService` and `ExerciseService` live here rather than in the
/// shared package. `Database` implements both; each shared method delegates to
/// its `OrExisting` twin and drops the flag.
///
/// The second element is `true` when this call minted the row, `false` when
/// the id (or, for folders, the case-insensitive name) already named a row the
/// caller owns and that row came back untouched. An id owned by someone else
/// is never returned: it surfaces as `403 id_taken`.
library;

import 'package:heart_models/heart_models.dart';

abstract interface class IdempotentGoalService implements GoalService {
  /// Goals carry no natural key, so the id is the only thing a retry can match
  /// on; a retry never counts against the active-goal cap.
  Future<(Goal, bool created)> createGoalOrExisting(Goal goal, String userId);
}

abstract interface class IdempotentTemplateService implements ApiTemplateService {
  /// Matches on [TemplateRequest.id] only; content is ignored on a hit.
  Future<(Template, bool created)> createTemplateOrExisting({required String userId, required TemplateRequest body});
}

abstract interface class IdempotentTemplateFolderService implements ApiTemplateFolderService {
  /// Matches on the folder's id or its case-insensitive name — the replay's
  /// name-merge case returns the account's folder under its own id.
  Future<(TemplateFolder, bool created)> createFolderOrExisting({
    required String userId,
    required TemplateFolder folder,
  });
}
