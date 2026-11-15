import 'package:heart/models/me.dart';
import 'package:heart_models/heart_models.dart';

// What `/me/coaching` answers: a coach's reads of the clients who share their
// training with the coach's assistant (docs/2026-11-09.coach-assistant.md).
// Shapes of their own rather than the app's, since `/me` is additive-only and
// the app's coaching shapes are not yet.

/// `GET /me/coaching/clients`: one person the user coaches. A client who doesn't
/// share with the assistant is named, with their status and since when, and no
/// more.
class MeCoachingClient implements Model {
  final ClientSummary client;

  const new(this.client);

  @override
  Map<String, dynamic> toMap() {
    return {
      'clientId': client.studentId,
      'name': ?client.name,
      'status': client.status,
      'since': ?client.acceptedAt?.toUtc().toIso8601String(),
      'sharesWithAssistant': client.assistant,
      if (client.programName case final String name)
        'program': {
          'name': name,
          'week': ?client.programWeek,
          'weeks': ?client.programWeeks,
        },
      'recent': [for (final at in client.recent) at.toUtc().toIso8601String()],
      'lastTrainedAt': ?client.lastTrainedAt?.toUtc().toIso8601String(),
      'reasons': client.reasons,
    };
  }
}

/// `GET /me/coaching/feed`: one thing a client did.
class MeCoachFeedItem implements Model {
  final CoachFeedItem item;

  const new(this.item);

  @override
  Map<String, dynamic> toMap() {
    return {
      'kind': item.kind,
      'id': item.id,
      'clientId': item.studentId,
      'name': ?item.name,
      'at': item.at.toUtc().toIso8601String(),
      'title': ?item.title,
    };
  }
}

/// A client's workout, as `/me/workouts` gives the user's own, and whether the
/// user logged it for them.
class MeClientWorkout implements Model {
  final Workout workout;

  /// The user, who coaches.
  final String coachId;

  const new(this.workout, {required this.coachId});

  String get id => workout.id;

  @override
  Map<String, dynamic> toMap() {
    return {
      ...MeWorkout(workout).toMap(),
      if (workout.loggedBy == coachId) 'loggedByYou': true,
    };
  }
}

/// `GET /me/coaching/clients/:clientId/programs`.
class MeClientPrograms implements Model {
  final Iterable<Program> programs;

  const new(this.programs);

  @override
  Map<String, dynamic> toMap() {
    return {
      'programs': [for (final program in programs) MeClientProgramSummary(program).toMap()],
    };
  }
}

/// One program the user sent a client, in a list.
class MeClientProgramSummary implements Model {
  final Program program;

  const new(this.program);

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': program.id,
      'name': program.name,
      'archived': program.archived,
      'sessions': program.sessions.length,
    };
  }
}

/// `GET /me/coaching/clients/:clientId/programs/:programId`: a program the user
/// sent, as the client holds it now, and where they stand in it.
class MeClientProgram implements Model {
  final Program program;
  final List<Template> sessions;
  final ProgramPosition position;

  /// The user, who coaches.
  final String coachId;

  const new(this.program, {required this.sessions, required this.position, required this.coachId});

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': program.id,
      'name': program.name,
      'note': ?program.note,
      'perWeek': ?program.perWeek,
      'weeks': ?program.weeks,
      'archived': program.archived,
      'position': position.toMap(),
      'sessions': [
        for (final session in sessions)
          MeClientSession(session, done: position.done.contains(session.id), coachId: coachId).toMap(),
      ],
    };
  }
}

/// One session of a client's program, as `/me/templates` gives a template.
class MeClientSession implements Model {
  final Template session;
  final bool done;

  /// The user, who coaches.
  final String coachId;

  const new(this.session, {required this.done, required this.coachId});

  @override
  Map<String, dynamic> toMap() {
    return {
      ...session.toMap(),
      'done': done,
      if (session.assignedBy?.id == coachId) 'sentByYou': true,
    };
  }
}

/// `GET /me/coaching/clients/:clientId/programs/:programId/changes`: a page of
/// the program's change feed, as `/me/workouts/changes` is a page of the user's.
class MeClientProgramChanges implements Model {
  final Page<ProgramChange> changes;

  /// Where this page started from, which is where the next starts when nothing
  /// changed.
  final String? since;

  /// The user, who coaches.
  final String coachId;
  final String clientId;

  const new(this.changes, {required this.since, required this.coachId, required this.clientId});

  @override
  Map<String, dynamic> toMap() {
    return {
      'changes': [
        for (final change in changes.items) MeClientProgramChange(change, coachId: coachId, clientId: clientId).toMap(),
      ],
      'cursor': ?(changes.items.isEmpty ? since : changes.items.last.cursor),
      'hasMore': changes.hasMore,
    };
  }
}

/// One change to a program the user sent a client.
class MeClientProgramChange implements Model {
  final ProgramChange change;

  /// The user, who coaches.
  final String coachId;
  final String clientId;

  const new(this.change, {required this.coachId, required this.clientId});

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': change.id,
      'at': change.at.toUtc().toIso8601String(),
      'by': ?switch (change.actorId) {
        final id when id == coachId => 'you',
        final id when id == clientId => 'client',
        _ => null,
      },
      'kind': change.kind,
      'sessionId': ?change.sessionId,
      'before': ?change.before,
      'after': ?change.after,
    };
  }
}

/// `GET /me/coaching/library`: one program of the user's own coaching library.
class MeLibraryEntry implements Model {
  final CoachProgram program;

  const new(this.program);

  String get id => program.id;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': program.id,
      'name': program.name,
      'version': program.version,
      'updatedAt': program.updatedAt.toUtc().toIso8601String(),
    };
  }
}

/// `GET /me/coaching/library/:programId`: one program of the user's coaching
/// library, its current version in full, as they saved it.
class MeLibraryProgram implements Model {
  final CoachProgram program;

  const new(this.program);

  @override
  Map<String, dynamic> toMap() {
    return {
      ...?program.body,
      // the server's own say, over anything the body carries
      ...MeLibraryEntry(program).toMap(),
    };
  }
}
