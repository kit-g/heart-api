import 'package:heart_models/heart_models.dart';

/// Where a coach stands on a copy: [readable] with a coach's view of the student,
/// [writable] across the live connection it came through.
typedef CopyAccess = ({bool readable, bool writable});

/// Two people on one copy of a program. Only a copy a coach sent pays for any of
/// this: on a person's own program each of these says so, and the plain route runs.
abstract interface class ProgramChangeService {
  /// Writes a session of a copy, recording it. Null if [sessionId] isn't one, or isn't
  /// one of [programId] when that's given, so the plain path applies. Throws `409 program_changed` when someone else changed this
  /// session since [baseRevision]. A [changeId] already seen does nothing. Without a
  /// [baseRevision] it's an old build: accepted, and recorded as stale.
  Future<Template?> writeSession({
    required String ownerId,
    required String actorId,
    required String sessionId,
    required TemplateRequest body,
    String? programId,
    int? baseRevision,
    String? changeId,
    String kind = 'edit',
  });

  /// Adds a session to a copy, or puts a deleted one back under its own ids, with
  /// the workouts and skips [links] names linked to it again. Refuses an id already in
  /// use, so it can't take over a template that isn't this copy's. Over a
  /// [baseRevision], `409 program_changed` when someone else changed it since, its
  /// deletion included. [changeId] makes a retried write the same change.
  Future<Template> restoreSession({
    required String ownerId,
    required String actorId,
    required String programId,
    required TemplateRequest body,
    Map<String, dynamic>? links,
    int? baseRevision,
    String? changeId,
    String kind = 'create',
  });

  /// Deletes a session of a copy, recording who named it, and answers the program it
  /// was in. Null if it isn't one, or isn't one of [programId] when that's given.
  /// Over a [baseRevision], as [writeSession] is.
  Future<String?> removeSession({
    required String ownerId,
    required String actorId,
    required String sessionId,
    String? programId,
    int? baseRevision,
    String kind = 'delete',
  });

  /// The same for the copy's own fields. Null if [programId] isn't a copy.
  Future<Program?> writeProgramFields({
    required String ownerId,
    required String actorId,
    required String programId,
    required Program program,
    int? baseRevision,
    String? changeId,
    String kind = 'edit',
  });

  /// What changed on a copy, in stored order, after [since].
  Future<List<ProgramChange>> getProgramChanges({required String ownerId, required String programId, String? since});

  /// One change, and the links it kept. Null if it isn't one of this copy's.
  Future<({ProgramChange change, Map<String, dynamic>? links})?> getProgramChange({
    required String ownerId,
    required String programId,
    required String changeId,
  });

  Future<CopyAccess> getCopyAccess({required String coachId, required String studentId, required String programId});

  /// The copies this coach sent this student.
  Future<List<Program>> getCopies({required String coachId, required String studentId});

  /// A copy's workouts and skips that [readerId] can read, as its position reads them.
  Future<Iterable<ProgramMark>> getVisibleMarks({
    required String readerId,
    required String ownerId,
    required String programId,
  });

  /// The copy's map from library ids to its own, and records the version it now holds.
  Future<Map<String, String>> getCopyIds({required String ownerId, required String programId});

  Future<void> setCopyVersion({
    required String ownerId,
    required String programId,
    required int version,
    required Map<String, String> ids,
  });

  /// Who to tell a copy changed: the other person from [actorId], if the copy is one.
  Future<String?> otherSideOf({required String actorId, required String programId});

  /// Whether [coachId] can log for and write to [studentId] right now.
  Future<bool> canLogFor({required String coachId, required String studentId});

  /// What a device planned for [userId]'s workout, as it stood. Doing it again keeps
  /// the first, since it's what was asked at the time. With [loggedBy], only on a
  /// workout that coach logged, so a coach can't plant one on the student's own.
  Future<void> savePlan({
    required String userId,
    required String workoutId,
    required Map<String, dynamic> plan,
    String? loggedBy,
  });

  /// Through the read policy; null if there's none or it's past what they can read.
  Future<Map<String, dynamic>?> getPlan({
    required String readerId,
    required String ownerId,
    required String workoutId,
  });
}
