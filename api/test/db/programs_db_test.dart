@Tags(['db'])
library;

import 'package:heart/db/db.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `ProgramService` query strings, and of the
/// template writes that carry a program and a note, against a live Postgres.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String exerciseId;

  Program program({String? id, String name = 'Getting stronger'}) {
    return Program(
      id: id,
      name: name,
      perWeek: 3,
      days: {1, 3, 5},
      weeks: 12,
      source: 'getting_stronger_1',
      rules: {exerciseId: const AddWeight(step: 2.5)},
    );
  }

  TemplateRequest session(String userId, String name, int order, {String? id, String? folderId}) {
    return TemplateRequest(
      userId: userId,
      id: id,
      name: name,
      order: order,
      folderId: folderId,
      note: 'why $name',
      exercises: [
        TemplateExerciseRequest(
          exerciseId: exerciseId,
          order: 0,
          sets: [const TemplateSetRequest(weight: 60, reps: 5)],
        ),
      ],
    );
  }

  Future<int> count(String sql, Map<String, dynamic> params) async {
    final rows = await h.exec(sql, params);
    return rows.first.toColumnMap()['n'] as int;
  }

  setUpAll(() async {
    await h.setupDatabase();
    exerciseId = await h.seedGlobalExercise();
  });

  tearDownAll(h.teardownDatabase);

  group('createProgramOrExisting', () {
    test('creates the program and its sessions, in order, as templates of it', () async {
      final userId = await h.seedProfile();
      final (created, isNew) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'B', 1), session(userId, 'A', 0)],
      );

      expect(isNew, isTrue);
      expect(created.name, 'Getting stronger');
      expect(created.perWeek, 3);
      expect(created.days, {1, 3, 5});
      expect(created.rules[exerciseId], const AddWeight(step: 2.5));
      expect(created.sessions, hasLength(2));

      final first = await h.db.getTemplate(userId: userId, templateId: created.sessions.first);
      expect(first.name, 'A');
      expect(first.programId, created.id);
      expect(first.note, 'why A');
      expect(first.single.single.reps, 5);
    });

    test('a replay returns the stored program and writes no sessions twice', () async {
      final userId = await h.seedProfile();
      final id = uuidV7();
      final body = program(id: id);
      await h.db.createProgramOrExisting(userId: userId, program: body, sessions: [session(userId, 'A', 0)]);
      final (again, isNew) = await h.db.createProgramOrExisting(
        userId: userId,
        program: body,
        sessions: [session(userId, 'A', 0)],
      );

      expect(isNew, isFalse);
      expect(again.id, id);
      expect(await count('SELECT count(*) AS n FROM templates WHERE program_id = @id::uuid', {'id': id}), 1);
    });

    test("another user's program id is id_taken", () async {
      final owner = await h.seedProfile();
      final stranger = await h.seedProfile();
      final id = uuidV7();
      await h.db.createProgramOrExisting(
        userId: owner,
        program: program(id: id),
        sessions: const [],
      );

      expect(
        () => h.db.createProgramOrExisting(
          userId: stranger,
          program: program(id: id),
          sessions: const [],
        ),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    test('a session filed in a folder the user does not own leaves nothing behind', () async {
      final userId = await h.seedProfile();
      final id = uuidV7();

      await expectLater(
        h.db.createProgramOrExisting(
          userId: userId,
          program: program(id: id),
          sessions: [session(userId, 'A', 0, folderId: uuidV7())],
        ),
        throwsA(isA<NotFound>()),
      );
      expect(await count('SELECT count(*) AS n FROM programs WHERE id = @id::uuid', {'id': id}), 0);
    });

    test('stops at the cap, archived programs included', () async {
      final userId = await h.seedProfile();
      await h.exec(
        '''
INSERT INTO programs (user_id, name, archived)
SELECT @userId, 'p' || n, n % 2 = 0
FROM generate_series(1, 100) n
''',
        {'userId': userId},
      );

      expect(
        () => h.db.createProgramOrExisting(userId: userId, program: program(), sessions: const []),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'program_limit')),
      );
    });
  });

  group('getPrograms and getProgram', () {
    test('list only the caller\'s programs', () async {
      final owner = await h.seedProfile();
      final stranger = await h.seedProfile();
      final (mine, _) = await h.db.createProgramOrExisting(userId: owner, program: program(), sessions: const []);

      expect((await h.db.getPrograms(owner)).map((p) => p.id), [mine.id]);
      expect(await h.db.getPrograms(stranger), isEmpty);
      expect(
        () => h.db.getProgram(userId: stranger, programId: mine.id!),
        throwsA(isA<NotFound>().having((e) => e.code, 'code', 'program_not_found')),
      );
    });
  });

  group('updateProgram', () {
    test('replaces the fields, keeps the source and the sessions', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'A', 0)],
      );

      final updated = await h.db.updateProgram(
        userId: userId,
        programId: stored.id!,
        program: Program(name: 'Renamed', perWeek: 2, archived: true, rules: {exerciseId: const NoGrowth()}),
      );

      expect(updated.name, 'Renamed');
      expect(updated.perWeek, 2);
      expect(updated.days, isEmpty);
      expect(updated.weeks, isNull);
      expect(updated.archived, isTrue);
      expect(updated.rules[exerciseId], const NoGrowth());
      expect(updated.source, 'getting_stronger_1');
      expect(updated.sessions, stored.sessions);
    });

    test("someone else's program is not found", () async {
      final owner = await h.seedProfile();
      final stranger = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(userId: owner, program: program(), sessions: const []);

      expect(
        () => h.db.updateProgram(userId: stranger, programId: stored.id!, program: program()),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('deleteProgram', () {
    test('deletes its sessions with it', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'A', 0)],
      );

      await h.db.deleteProgram(userId: userId, programId: stored.id!);

      expect(
        await count('SELECT count(*) AS n FROM templates WHERE id = @id::uuid', {'id': stored.sessions.single}),
        0,
      );
    });

    test('keepTemplates leaves them as plain templates', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'A', 0)],
      );

      await h.db.deleteProgram(userId: userId, programId: stored.id!, keepTemplates: true);

      final kept = await h.db.getTemplate(userId: userId, templateId: stored.sessions.single);
      expect(kept.programId, isNull);
      expect(await h.db.getPrograms(userId), isEmpty);
    });
  });

  group('templates as sessions', () {
    test('an update without the keys keeps the program and the note', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'A', 0)],
      );
      final templateId = stored.sessions.single;

      final updated = await h.db.updateTemplate(
        userId: userId,
        templateId: templateId,
        body: TemplateRequest(userId: userId, name: 'A, renamed by 1.13'),
      );

      expect(updated.programId, stored.id);
      expect(updated.note, 'why A');
    });

    test('an explicit null detaches and clears; an id attaches', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(
        userId: userId,
        program: program(),
        sessions: [session(userId, 'A', 0)],
      );
      final templateId = stored.sessions.single;

      final detached = await h.db.updateTemplate(
        userId: userId,
        templateId: templateId,
        body: TemplateRequest(userId: userId, name: 'A', movesProgram: true, changesNote: true),
      );
      expect(detached.programId, isNull);
      expect(detached.note, isNull);
      expect((await h.db.getProgram(userId: userId, programId: stored.id!)).sessions, isEmpty);

      final attached = await h.db.updateTemplate(
        userId: userId,
        templateId: templateId,
        body: TemplateRequest(userId: userId, name: 'A', programId: stored.id, movesProgram: true),
      );
      expect(attached.programId, stored.id);
    });

    test("a template can't join someone else's program", () async {
      final owner = await h.seedProfile();
      final stranger = await h.seedProfile();
      final (theirs, _) = await h.db.createProgramOrExisting(userId: owner, program: program(), sessions: const []);

      Object? error;
      try {
        await h.db.createTemplate(
          userId: stranger,
          body: TemplateRequest(userId: stranger, name: 'sneaky', programId: theirs.id),
        );
      } catch (e) {
        error = e;
      }
      expect(apiExceptionForDbError(error!), isA<NotFound>().having((e) => e.code, 'code', 'unknown_program'));
    });
  });

  group('actions', () {
    test('created idempotently, listed in the order taken, deleted to undo', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(userId: userId, program: program(), sessions: const []);
      final programId = stored.id!;
      final pause = ProgramAction(id: uuidV7(), kind: .pause, at: DateTime.utc(2026, 10, 2));

      final (first, isNew) = await h.db.createProgramAction(userId: userId, programId: programId, action: pause);
      final (again, againNew) = await h.db.createProgramAction(userId: userId, programId: programId, action: pause);
      await h.db.createProgramAction(
        userId: userId,
        programId: programId,
        action: ProgramAction(kind: .replay, week: 2, at: DateTime.utc(2026, 10, 1)),
      );

      expect((isNew, againNew), (true, false));
      expect(again.id, first.id);
      final listed = await h.db.getProgramActions(userId: userId, programId: programId);
      expect(listed.map((a) => a.kind), [ProgramActionKind.replay, ProgramActionKind.pause]);
      expect(listed.first.week, 2);

      await h.db.deleteProgramAction(userId: userId, programId: programId, actionId: first.id!);
      expect(await h.db.getProgramActions(userId: userId, programId: programId), hasLength(1));
    });

    test("someone else's program is unknown_program, and its actions are invisible", () async {
      final owner = await h.seedProfile();
      final stranger = await h.seedProfile();
      final (theirs, _) = await h.db.createProgramOrExisting(userId: owner, program: program(), sessions: const []);
      await h.db.createProgramAction(
        userId: owner,
        programId: theirs.id!,
        action: ProgramAction(kind: .pause, at: DateTime.utc(2026, 10, 1)),
      );

      expect(await h.db.getProgramActions(userId: stranger, programId: theirs.id!), isEmpty);
      Object? error;
      try {
        await h.db.createProgramAction(
          userId: stranger,
          programId: theirs.id!,
          action: ProgramAction(kind: .pause, at: DateTime.utc(2026, 10, 1)),
        );
      } catch (e) {
        error = e;
      }
      expect(apiExceptionForDbError(error!), isA<NotFound>().having((e) => e.code, 'code', 'unknown_program'));
    });
  });

  group('bases', () {
    test('one move per workout: a second device replaying the bump gets the first back', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(userId: userId, program: program(), sessions: const []);
      final workoutId = await h.seedWorkout(userId: userId);
      ProgramBase bump() => ProgramBase(
        id: uuidV7(),
        exerciseId: exerciseId,
        value: 102.5,
        workoutId: workoutId,
        at: DateTime.utc(2026, 10, 14),
      );

      final (first, isNew) = await h.db.createProgramBase(userId: userId, programId: stored.id!, base: bump());
      final (second, secondNew) = await h.db.createProgramBase(userId: userId, programId: stored.id!, base: bump());

      expect((isNew, secondNew), (true, false));
      expect(second.id, first.id);
      expect(await h.db.getProgramBases(userId: userId, programId: stored.id!), hasLength(1));
    });

    test('deleting the workout or the action deletes the move it caused', () async {
      final userId = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(userId: userId, program: program(), sessions: const []);
      final programId = stored.id!;
      final workoutId = await h.seedWorkout(userId: userId);
      final (replay, _) = await h.db.createProgramAction(
        userId: userId,
        programId: programId,
        action: ProgramAction(kind: .replay, week: 1, at: DateTime.utc(2026, 10, 3)),
      );
      for (final base in [
        ProgramBase(exerciseId: exerciseId, value: 100, at: DateTime.utc(2026, 10, 1)),
        ProgramBase(exerciseId: exerciseId, value: 102.5, workoutId: workoutId, at: DateTime.utc(2026, 10, 2)),
        ProgramBase(exerciseId: exerciseId, value: 92.5, actionId: replay.id, at: DateTime.utc(2026, 10, 3)),
      ]) {
        await h.db.createProgramBase(userId: userId, programId: programId, base: base);
      }

      await h.exec('DELETE FROM workouts WHERE id = @id::uuid', {'id': workoutId});
      await h.db.deleteProgramAction(userId: userId, programId: programId, actionId: replay.id!);

      final left = await h.db.getProgramBases(userId: userId, programId: programId);
      expect(left.single.value, 100);
      expect(left.single.isManual, isTrue);
    });

    test("an exercise the caller can't see, or a workout they don't own, is not found", () async {
      final userId = await h.seedProfile();
      final stranger = await h.seedProfile();
      final (stored, _) = await h.db.createProgramOrExisting(userId: userId, program: program(), sessions: const []);
      final theirWorkout = await h.seedWorkout(userId: stranger);

      expect(
        () => h.db.createProgramBase(
          userId: userId,
          programId: stored.id!,
          base: ProgramBase(exerciseId: uuidV7(), value: 100, at: DateTime.utc(2026, 10, 1)),
        ),
        throwsA(isA<NotFound>().having((e) => e.code, 'code', 'unknown_exercise')),
      );
      expect(
        () => h.db.createProgramBase(
          userId: userId,
          programId: stored.id!,
          base: ProgramBase(exerciseId: exerciseId, value: 100, workoutId: theirWorkout, at: DateTime.utc(2026, 10, 1)),
        ),
        throwsA(isA<NotFound>().having((e) => e.code, 'code', 'unknown_workout')),
      );
    });
  });
}

class _Harness extends DatabaseTestBase;
