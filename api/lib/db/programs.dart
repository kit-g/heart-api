part of 'db.dart';

mixin _Programs on _DatabaseBase implements ProgramService {
  @override
  Future<Iterable<Program>> getPrograms(String userId) async {
    final rows = await _pool.execute(_listPrograms.toSql(), parameters: {'userId': userId});
    return rows.map((row) => Program.fromRow(row.toColumnMap()));
  }

  @override
  Future<Program> getProgram({required String userId, required String programId}) async {
    return _readProgram(_pool, userId: userId, programId: programId);
  }

  @override
  Future<(Program, bool created)> createProgramOrExisting({
    required String userId,
    required Program program,
    required List<TemplateRequest> sessions,
  }) async {
    try {
      return await _retryOnCreateRace(
        () => _pool.runTx((tx) async {
          final rows = await tx.execute(
            _createProgram.toSql(),
            parameters: {'id': program.id, 'userId': userId, ..._programParams(program)},
          );
          // The id pre-check has ruled out "this id is mine", and a foreign id
          // trips programs_pkey, so an empty result can only be the cap.
          if (rows.isEmpty) {
            throw const BadRequest(
              code: 'program_limit',
              reason: 'you can have at most $_maxPrograms programs; delete one first',
            );
          }
          final row = rows.first.toColumnMap();
          final id = row['id'].toString();
          final created = row['created'] as bool;
          if (created) {
            for (final session in sessions) {
              final saved = await tx.execute(
                _saveTemplate.toSql(),
                parameters: {
                  'id': session.id,
                  ...session.toParams(),
                  'programId': id,
                  'joined': session.joined,
                  'note': session.note,
                },
              );
              if (saved.isEmpty) throw NotFound(type: 'TemplateFolder', id: session.folderId ?? '');
            }
          }
          return (await _readProgram(tx, userId: userId, programId: id), created);
        }),
      );
    } on ServerException catch (e) {
      _rethrowClientIdCollision(e);
    }
  }

  @override
  Future<Program> updateProgram({required String userId, required String programId, required Program program}) async {
    final rows = await _pool.execute(
      _replaceProgram.toSql(),
      parameters: {
        'id': programId,
        'userId': userId,
        ..._programParams(program)..remove('source'),
        'archived': program.archived,
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
    return Program.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<void> deleteProgram({required String userId, required String programId, bool keepTemplates = false}) async {
    final parameters = {'id': programId, 'userId': userId};
    await _pool.runTx((tx) async {
      if (keepTemplates) await tx.execute(_detachProgramTemplates.toSql(), parameters: parameters);
      await tx.execute(_deleteProgram.toSql(), parameters: parameters);
    });
  }

  @override
  Future<Iterable<ProgramAction>> getProgramActions({required String userId, required String programId}) async {
    final rows = await _pool.execute(
      _listProgramActions.toSql(),
      parameters: {'userId': userId, 'programId': programId},
    );
    return rows.map((row) => ProgramAction.fromRow(row.toColumnMap()));
  }

  @override
  Future<(ProgramAction, bool created)> createProgramAction({
    required String userId,
    required String programId,
    required ProgramAction action,
  }) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createProgramAction.toSql(),
          parameters: {
            'id': action.id,
            'userId': userId,
            'programId': programId,
            'kind': action.kind.value,
            'week': action.week,
            'at': action.at.toUtc(),
          },
        ),
      );
      if (rows.isEmpty) {
        throw const BadRequest(
          code: 'program_history_limit',
          reason: 'a program keeps at most $_maxProgramActions actions',
        );
      }
      final row = rows.first.toColumnMap();
      return (ProgramAction.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<void> deleteProgramAction({
    required String userId,
    required String programId,
    required String actionId,
  }) async {
    await _pool.execute(
      _deleteProgramAction.toSql(),
      parameters: {'id': actionId, 'programId': programId, 'userId': userId},
    );
  }

  @override
  Future<Iterable<ProgramBase>> getProgramBases({required String userId, required String programId}) async {
    final rows = await _pool.execute(
      _listProgramBases.toSql(),
      parameters: {'userId': userId, 'programId': programId},
    );
    return rows.map((row) => ProgramBase.fromRow(row.toColumnMap()));
  }

  @override
  Future<(ProgramBase, bool created)> createProgramBase({
    required String userId,
    required String programId,
    required ProgramBase base,
  }) async {
    final references = {'userId': userId, 'exerciseId': base.exerciseId, 'workoutId': base.workoutId};
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createProgramBase.toSql(),
          parameters: {
            ...references,
            'id': base.id,
            'programId': programId,
            'slot': base.slot,
            'value': base.value,
            'actionId': base.actionId,
            'at': base.at.toUtc(),
          },
        ),
      );
      if (rows.isEmpty) {
        final diagnosis = (await _pool.execute(
          _diagnoseProgramBase.toSql(),
          parameters: references,
        )).first.toColumnMap();
        if (diagnosis['exercise_known'] != true) {
          throw NotFound(type: 'Exercise', id: base.exerciseId, code: 'unknown_exercise');
        }
        if (diagnosis['workout_known'] != true) {
          throw NotFound(type: 'Workout', id: base.workoutId ?? '', code: 'unknown_workout');
        }
        throw const BadRequest(
          code: 'program_history_limit',
          reason: 'a program keeps at most $_maxProgramBases bases',
        );
      }
      final row = rows.first.toColumnMap();
      return (ProgramBase.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<void> deleteProgramBase({required String userId, required String programId, required String baseId}) async {
    await _pool.execute(
      _deleteProgramBase.toSql(),
      parameters: {'id': baseId, 'programId': programId, 'userId': userId},
    );
  }

  @override
  Future<Iterable<ProgramMark>> getProgramMarks({required String userId, required String programId}) async {
    final rows = await _pool.execute(
      _listProgramMarks.toSql(),
      parameters: {'userId': userId, 'programId': programId},
    );
    return rows.map((row) {
      final map = row.toColumnMap();
      return ProgramMark(
        templateId: map['template_id']?.toString(),
        at: map['at'] as DateTime,
        isWorkout: map['is_workout'] as bool,
      );
    });
  }

  Future<Program> _readProgram(Session session, {required String userId, required String programId}) async {
    final rows = await session.execute(_getProgram.toSql(), parameters: {'id': programId, 'userId': userId});
    if (rows.isEmpty) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
    return Program.fromRow(rows.first.toColumnMap());
  }

  /// The program's own fields, as `_createProgram` and `_replaceProgram` take them.
  /// The rules go as the program writes them, unread ones included, so a save
  /// never drops a rule a newer build wrote.
  Map<String, dynamic> _programParams(Program program) {
    final map = program.toMap();
    return {
      'name': program.name,
      'note': program.note,
      'source': program.source,
      'perWeek': program.perWeek,
      'days': map['days'] ?? const <int>[],
      'weeks': program.weeks,
      'rules': jsonEncode(map['rules']),
      'constraintKey': program.constraint,
    };
  }
}
