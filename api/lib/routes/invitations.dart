import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> createInvitation(Request req) async {
  final input = await InvitationCreateIn.fromRequest(req);
  final invitation = await req.invitationService.createInvitation(
    inviterId: req.userId,
    name: input.name,
    domain: input.domain,
    token: TokenSecret.random(),
  );
  return Created(invitation);
}

Future<Paginated<Invitation>> getInvitations(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.invitationService.getInvitations(
    inviterId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<Invitation>.from(page, itemsKey: 'invitations', cursorOf: (invitation) => invitation.id);
}

Future<Model> cancelInvitation(Request req) async {
  await req.invitationService.cancelInvitation(
    inviterId: req.userId,
    invitationId: req.rawPathParameters[#invitationId]!,
  );
  throw const NoContent();
}

Future<Invitation> resendInvitation(Request req) {
  return req.invitationService.renewInvitation(
    inviterId: req.userId,
    invitationId: req.rawPathParameters[#invitationId]!,
    token: TokenSecret.random(),
  );
}

/// Signed out: all a link says is who is asking and whether it's good.
Future<InvitationPreview> previewInvitation(Request req) async {
  final preview = await req.invitationService.previewInvitation(token: req.rawPathParameters[#token]!);
  return preview ?? (throw const NotFound(type: 'Invitation', id: 'that link'));
}

Future<Connection> acceptInvitation(Request req) async {
  final input = await InvitationAcceptIn.fromRequest(req);
  return req.invitationService.acceptInvitation(
    userId: req.userId,
    token: req.rawPathParameters[#token]!,
    shares: input.shares,
  );
}

Future<Model> declineInvitation(Request req) async {
  await req.invitationService.declineInvitation(userId: req.userId, token: req.rawPathParameters[#token]!);
  throw const NoContent();
}

Future<Model> blockInviter(Request req) async {
  await req.invitationService.blockInviter(userId: req.userId, token: req.rawPathParameters[#token]!);
  throw const NoContent();
}

Future<Paginated<BlockedPerson>> getBlocks(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.invitationService.getBlocks(userId: req.userId, cursor: query.cursor, limit: query.limit);
  return Paginated<BlockedPerson>.from(page, itemsKey: 'blocks', cursorOf: (person) => person.id);
}

Future<Model> liftBlock(Request req) async {
  await req.invitationService.liftBlock(userId: req.userId, blockedId: req.rawPathParameters[#blockedId]!);
  throw const NoContent();
}
