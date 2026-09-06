import '../models/shares.dart';
import '../models/template_folder.dart';

/// Server-side folder operations. Folders are flat and owner-scoped, so every
/// call carries the owner's id and nothing here takes a parent.
abstract interface class ApiTemplateFolderService {
  /// Every folder the user owns, each with its template count. Unpaginated —
  /// folders are a handful per user, not a feed.
  Future<Iterable<TemplateFolder>> getFolders({required String userId});

  /// `created` is true when this call minted the row; false when [folder]'s
  /// id or (case-insensitive) name already named a folder the caller owns —
  /// the upsync replay's idempotent-retry / name-merge cases
  /// (kit-g/heart-api#66) — in which case the existing folder comes back
  /// untouched, under its own id.
  Future<(TemplateFolder, bool created)> createFolder({required String userId, required TemplateFolder folder});

  Future<TemplateFolder> updateFolder({
    required String userId,
    required String folderId,
    required TemplateFolder folder,
  });

  /// Deletes the folder and unfiles — never deletes — the templates inside it.
  Future<void> deleteFolder({required String userId, required String folderId});

  /// Assigns every template in the folder to [targetUserId], as if each had been
  /// assigned individually: one [TemplateShare] per template, idempotent per
  /// template, and the recipient's copies arrive unfiled.
  ///
  /// A snapshot, not a subscription — templates added to the folder afterwards
  /// do not follow.
  Future<Iterable<TemplateShare>> shareFolder({
    required String coachId,
    required String targetUserId,
    required String folderId,
  });
}
