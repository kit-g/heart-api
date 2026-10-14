import 'package:heart_models/heart_models.dart';

/// The user's programs (heart-api#86, `docs/2026-10-13.programs.md`).
///
/// API-side rather than in `heart_models`: the app keeps programs in its own
/// local database and never implements this, so it can grow without touching
/// a shared contract.
abstract interface class ProgramService {
  /// Every program the user has, archived ones included.
  Future<Iterable<Program>> getPrograms(String userId);

  Future<Program> getProgram({required String userId, required String programId});

  /// Creates [program] and its [sessions] as templates of it, in one
  /// transaction: starting a library program is this call, with the copy made
  /// on the device. Idempotent on the program's id, as the other creates are
  /// (heart-api#66); a hit returns the stored program and writes no sessions.
  Future<(Program, bool created)> createProgramOrExisting({
    required String userId,
    required Program program,
    required List<TemplateRequest> sessions,
  });

  /// A full replace of the program's own fields. Sessions change through their
  /// templates.
  Future<Program> updateProgram({required String userId, required String programId, required Program program});

  /// Deletes the program and, unless [keepTemplates], its session templates.
  Future<void> deleteProgram({required String userId, required String programId, bool keepTemplates = false});

  /// The program's steps in the order they were taken.
  Future<Iterable<ProgramAction>> getProgramActions({required String userId, required String programId});

  /// Idempotent on the action's id.
  Future<(ProgramAction, bool created)> createProgramAction({
    required String userId,
    required String programId,
    required ProgramAction action,
  });

  /// Undoes a step. Deleting what isn't there is not an error.
  Future<void> deleteProgramAction({required String userId, required String programId, required String actionId});

  /// Every base of the program, oldest first.
  Future<Iterable<ProgramBase>> getProgramBases({required String userId, required String programId});

  /// Idempotent on the base's id, and on its exercise and workout together.
  Future<(ProgramBase, bool created)> createProgramBase({
    required String userId,
    required String programId,
    required ProgramBase base,
  });

  Future<void> deleteProgramBase({required String userId, required String programId, required String baseId});
}

abstract interface class ProgramsResponse implements Model {
  Iterable<Program> get programs;

  factory({required Iterable<Program> programs}) = _ProgramsResponse.new;
}

class _ProgramsResponse implements ProgramsResponse {
  @override
  final Iterable<Program> programs;

  new({required this.programs});

  @override
  Map<String, dynamic> toMap() {
    return {
      'programs': programs.map((each) => each.toMap()).toList(),
    };
  }
}

abstract interface class ProgramActionsResponse implements Model {
  Iterable<ProgramAction> get actions;

  factory({required Iterable<ProgramAction> actions}) = _ProgramActionsResponse.new;
}

class _ProgramActionsResponse implements ProgramActionsResponse {
  @override
  final Iterable<ProgramAction> actions;

  new({required this.actions});

  @override
  Map<String, dynamic> toMap() {
    return {
      'actions': actions.map((each) => each.toMap()).toList(),
    };
  }
}

abstract interface class ProgramBasesResponse implements Model {
  Iterable<ProgramBase> get bases;

  factory({required Iterable<ProgramBase> bases}) = _ProgramBasesResponse.new;
}

class _ProgramBasesResponse implements ProgramBasesResponse {
  @override
  final Iterable<ProgramBase> bases;

  new({required this.bases});

  @override
  Map<String, dynamic> toMap() {
    return {
      'bases': bases.map((each) => each.toMap()).toList(),
    };
  }
}
