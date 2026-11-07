import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart/routes/coach_library.dart';
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
  if (input.programId case final String programId) {
    await req.coachLibraryService.attachInvitationProgram(
      coachId: req.userId,
      invitationId: invitation.id,
      programId: programId,
    );
  }
  return Created(invitation);
}

Future<Paginated<Invitation>> getInvitations(Request req) async {
  final query = InvitationsQuery.fromRequest(req);
  final page = await req.invitationService.getInvitations(
    inviterId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<Invitation>.from(page, itemsKey: 'invitations', cursorOf: (invitation) => invitation.id);
}

Future<Model> cancelInvitation(Request req) async {
  await req.invitationService.cancelInvitation(inviterId: req.userId, invitationId: _invitationId(req));
  throw const NoContent();
}

Future<Invitation> resendInvitation(Request req) {
  return req.invitationService.renewInvitation(
    inviterId: req.userId,
    invitationId: _invitationId(req),
    token: TokenSecret.random(),
  );
}

String _invitationId(Request req) {
  final id = req.rawPathParameters[#invitationId]!;
  return isUuidV7(id) ? id : throw NotFound(type: 'Invitation', id: id);
}

/// Signed out: all a link says is who is asking and whether it's good.
Future<InvitationPreview> previewInvitation(Request req) async {
  final preview = await req.invitationService.previewInvitation(token: req.rawPathParameters[#token]!);
  return preview ?? (throw const NotFound(type: 'Invitation', id: 'that link'));
}

Future<AcceptedInvitation> acceptInvitation(Request req) async {
  final input = await InvitationAcceptIn.fromRequest(req);
  final token = req.rawPathParameters[#token]!;
  final program = await req.coachLibraryService.invitationProgram(token: token);
  final connection = await req.invitationService.acceptInvitation(
    userId: req.userId,
    token: token,
    shares: input.shares,
    email: req.user.email,
    name: req.user.displayName,
  );
  await req.events.publish(
    queueUrl: req.config.eventsQueueUrl,
    message: {
      'type': 'push.requested',
      'userId': connection.targetId,
      'topic': PushTopic.invitationAccepted.key,
      'name': ?req.user.displayName,
      'actorId': req.userId,
      'connectionId': connection.connectionId,
    },
  );
  // a separate step: their limit shouldn't stop them connecting, and the coach
  // sees it didn't arrive and can send it again
  final delivery = switch (program) {
    final String id => await deliverCoachProgram(
      req,
      coachId: connection.targetId,
      id: id,
      connectionId: connection.connectionId!,
    ),
    null => null,
  };
  return AcceptedInvitation(connection, delivery: delivery);
}

Future<Model> declineInvitation(Request req) async {
  await req.invitationService.declineInvitation(
    userId: req.userId,
    token: req.rawPathParameters[#token]!,
    email: req.user.email,
    name: req.user.displayName,
  );
  throw const NoContent();
}

Future<Model> blockInviter(Request req) async {
  await req.invitationService.blockInviter(
    userId: req.userId,
    token: req.rawPathParameters[#token]!,
    email: req.user.email,
    name: req.user.displayName,
  );
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
