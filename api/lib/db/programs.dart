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
