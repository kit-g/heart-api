import 'package:heart_models/heart_models.dart';

typedef CoachSendContext = ({
  int version,
  Map<String, dynamic> body,

  /// Null if there's no active coach relationship across that connection.
  String? studentId,
  String? existingProgramId,

  /// The student is on something else, so a new program waits for them to start it.
  bool studentBusy,
});

/// A coach's library and sending from it. API-side, like [ProgramService].
abstract interface class CoachLibraryService {
  /// Saves a new version, or the first one. Throws at the library's limit.
  Future<CoachProgram> saveCoachProgram({
    required String coachId,
    required String id,
    required String name,
    required Map<String, dynamic> body,
  });

  Future<Page<CoachProgram>> getCoachPrograms({required String coachId, String? cursor, int limit = 30});

  Future<CoachProgram> getCoachProgram({required String coachId, required String id});

  /// Copies already sent stay: a copy never follows its library program.
  Future<void> deleteCoachProgram({required String coachId, required String id});

  Future<List<CoachProgramHolder>> getCoachProgramHolders({required String coachId, required String id});

  /// What sending needs to know: the current version, whether this coach is
  /// coaching across that connection, and what the student already holds. Null if
  /// the program isn't this coach's.
  Future<CoachSendContext?> getCoachSendContext({
    required String coachId,
    required String id,
    required String connectionId,
  });

  /// For each of [ids] that is an exercise, the one [studentId] has: their own by
  /// that name, the library's, or a copy made for them.
  Future<Map<String, String>> matchExercisesForStudent({required List<String> ids, required String studentId});

  /// The program an invitation names, if any.
  Future<String?> invitationProgram({required String token});

  /// Sets the program [invitationId] starts with. It has to be [coachId]'s.
  Future<void> attachInvitationProgram({
    required String coachId,
    required String invitationId,
    required String programId,
  });

  /// A student starting a program that was waiting for them.
  Future<void> startProgram({required String userId, required String programId});
}
