import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/template_folders.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<TemplateFoldersResponse> getMyFolders(Request req) async {
  final folders = await req.templateFolderService.getFolders(userId: req.userId);
  return TemplateFoldersResponse(folders: folders);
}

Future<Model> createFolder(Request req) async {
  final input = await TemplateFolderCreateIn.fromRequest(req);
  final (folder, isNew) = await req.templateFolderService.createFolderOrExisting(
    userId: req.userId,
    folder: input.folder,
  );
  if (isNew) return Created(folder);
  return folder;
}

Future<TemplateFolder> updateFolder(Request req) {
  return updateFolderById(req, req.rawPathParameters[#folderId]!);
}

Future<TemplateFolder> updateFolderById(Request req, String folderId) async {
  final input = await TemplateFolderUpdateIn.fromRequest(req);
  return req.templateFolderService.updateFolder(
    userId: req.userId,
    folderId: folderId,
    folder: input.folder,
  );
}

Future<Model> deleteFolder(Request req) {
  return deleteFolderById(req, req.rawPathParameters[#folderId]!);
}

Future<Model> deleteFolderById(Request req, String folderId) async {
  await req.templateFolderService.deleteFolder(userId: req.userId, folderId: folderId);
  throw const NoContent();
}

/// `POST /accounts/:targetUserId/folders/:folderId` — assign every template in
/// the folder. Shorthand for assigning each one individually, so the same
/// permission gate and the same per-template idempotency apply.
Future<TemplateSharesResponse> assignFolderToUser(Request req) {
  return assignFolderToUserById(
    req,
    req.rawPathParameters[#targetUserId]!,
    req.rawPathParameters[#folderId]!,
  );
}

Future<TemplateSharesResponse> assignFolderToUserById(
  Request req,
  String targetUserId,
  String folderId,
) async {
  if (req.userId == targetUserId) {
    throw const Forbidden(reason: 'You cannot assign templates to yourself.');
  }

  final shares = await req.templateFolderService.shareFolder(
    coachId: req.userId,
    targetUserId: targetUserId,
    folderId: folderId,
  );
  return TemplateSharesResponse(shares: shares);
}
