import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/roster.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('Roster');

/// Works out what changed since the coach last looked, from what they can read,
/// so a coach pays only for that. Position is a fold in Dart, which is why this isn't
/// a query. A program counts as ending from its last week on.
Future<void> refreshRoster(Request req) async {
  final dirty = await req.rosterService.getDirtySummaries(coachId: req.userId);
  for (final summary in dirty) {
    try {
      await _refreshSummary(req, summary);
    } catch (error, stack) {
      // one client's data shouldn't take the coach's whole roster with it: this one
      // stays dirty and shows what it last showed
      _logger.warning('could not work out a summary for ${summary.connectionId}', error, stack);
    }
  }
}

Future<void> _refreshSummary(Request req, DirtySummary summary) async {
  final program = summary.program;
  final position = switch (program) {
    null => null,
    final Program copy => ProgramPosition.of(
      copy,
      marks: await req.programChangeService.getVisibleMarks(
        readerId: summary.coachId,
        ownerId: summary.studentId,
        programId: copy.id!,
      ),
      actions: await req.programService.getProgramActions(userId: summary.studentId, programId: copy.id!),
      now: DateTime.timestamp(),
    ),
  };
  final weeks = program?.weeks;
  await req.rosterService.refreshSummary(
    connectionId: summary.connectionId,
    coachId: summary.coachId,
    studentId: summary.studentId,
    generation: summary.generation,
    programId: program?.id,
    programName: program?.name,
    programWeek: position?.week,
    programWeeks: weeks,
    ending: weeks != null && position != null && position.week >= weeks,
  );
}

Future<Paginated<ClientSummary>> getRoster(Request req) async {
  final query = RosterQuery.fromRequest(req);
  await refreshRoster(req);
  final page = await req.rosterService.getRoster(
    coachId: req.userId,
    reason: query.reason,
    former: query.former,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<ClientSummary>.from(
    page,
    itemsKey: 'clients',
    cursorOf: (client) => '${!query.former && client.reasons.isEmpty ? 1 : 0}:${client.connectionId}',
  );
}

Future<Model> markClientReviewed(Request req) async {
  final input = await ClientReviewedIn.fromRequest(req);
  await req.rosterService.markReviewed(
    coachId: req.userId,
    connectionId: req.rawPathParameters[#connectionId]!,
    at: input.at,
  );
  throw const NoContent();
}

Future<Paginated<CoachFeedItem>> getCoachFeed(Request req) async {
  final query = PageTokenQuery.fromRequest(req);
  await refreshRoster(req);
  final page = await req.rosterService.getCoachFeed(coachId: req.userId, cursor: query.cursor, limit: query.limit);
  return Paginated<CoachFeedItem>.from(page, itemsKey: 'items', cursorOf: (item) => item.cursor!);
}
