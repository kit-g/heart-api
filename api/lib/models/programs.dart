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

  /// The program's workouts and skips, as its position reads them.
  Future<Iterable<ProgramMark>> getProgramMarks({required String userId, required String programId});

  /// The program's skips, oldest first.
  Future<Iterable<TrainingSkip>> getProgramSkips({required String userId, required String programId});

  /// The session each of the program's workouts was, by workout id; null for
  /// one that named none, or whose template is gone.
  Future<Map<String, String?>> getProgramWorkouts({required String userId, required String programId});
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

/// What caused a base: a workout's bump or cut, a test session, an action (a
/// replay's cut), or the user setting it.
enum BaseCause {
  workout('workout'),
  test('test'),
  action('action'),
  user('user');

  /// The `cause` on the wire.
  final String value;

  new(this.value);
}

/// A program's history read back (heart-api#260): every base with its cause
/// and the value it replaced, the actions, and the skips, each oldest first.
abstract interface class ProgramHistory implements Model {
  /// Every base, oldest first, with its cause and the value it replaced: the
  /// one before it for its slot, or for its exercise when it has no slot.
  List<({ProgramBase base, BaseCause cause, num? previous})> get bases;

  List<ProgramAction> get actions;

  List<TrainingSkip> get skips;

  /// [tests] are the program's test sessions and [sessions] the session of
  /// each of its workouts, as `getProgramWorkouts` reads them.
  factory({
    required Iterable<ProgramBase> bases,
    required Iterable<ProgramAction> actions,
    required Iterable<TrainingSkip> skips,
    required Set<String> tests,
    required Map<String, String?> sessions,
  }) = _ProgramHistory.new;
}

class _ProgramHistory implements ProgramHistory {
  @override
  final List<({ProgramBase base, BaseCause cause, num? previous})> bases;
  @override
  final List<ProgramAction> actions;
  @override
  final List<TrainingSkip> skips;

  factory({
    required Iterable<ProgramBase> bases,
    required Iterable<ProgramAction> actions,
    required Iterable<TrainingSkip> skips,
    required Set<String> tests,
    required Map<String, String?> sessions,
  }) {
    BaseCause causeOf(ProgramBase base) {
      return switch (base) {
        ProgramBase(workoutId: final String workout) when tests.contains(sessions[workout]) => .test,
        ProgramBase(workoutId: String()) => .workout,
        ProgramBase(actionId: String()) => .action,
        _ => .user,
      };
    }

    final held = <String, num>{};
    final timeline = <({ProgramBase base, BaseCause cause, num? previous})>[];
    for (final base in bases) {
      final key = base.slot ?? base.exerciseId;
      timeline.add((base: base, cause: causeOf(base), previous: held[key]));
      held[key] = base.value;
    }
    return _ProgramHistory._(timeline, actions.toList(), skips.toList());
  }

  new _(this.bases, this.actions, this.skips);

  @override
  Map<String, dynamic> toMap() {
    return {
      'bases': [
        for (final (:base, :cause, :previous) in bases)
          {...base.toMap()..remove('programId'), 'cause': cause.value, 'previous': ?previous},
      ],
      'actions': [for (final action in actions) action.toMap()..remove('programId')],
      'skips': [for (final skip in skips) skip.toMap()..remove('programId')],
    };
  }
}
