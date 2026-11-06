part of 'db.dart';

/// Library programs a coach can keep: a guard, never expected to bind.
const _maxCoachPrograms = 100;

mixin _CoachLibrary on _DatabaseBase implements CoachLibraryService {
  @override
  Future<CoachProgram> saveCoachProgram({
    required String coachId,
    required String id,
    required String name,
    required Map<String, dynamic> body,
  }) async {
    final rows = await _pool.execute(
      _saveCoachProgram.toSql(),
      parameters: {'coachId': coachId, 'id': id, 'name': name, 'body': jsonEncode(body)},
    );
    if (rows.isEmpty) {
      throw const BadRequest(code: 'library_limit', reason: 'a library holds at most $_maxCoachPrograms programs');
    }
    return CoachProgram.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<Page<CoachProgram>> getCoachPrograms({required String coachId, String? cursor, int limit = 30}) async {
    final rows = await _pool.execute(
      _listCoachPrograms.toSql(),
      parameters: {'coachId': coachId, 'cursor': cursor, 'limit': limit + 1},
    );
    final programs = rows.map((row) => CoachProgram.fromRow(row.toColumnMap())).toList();
    final hasMore = programs.length > limit;
    return Page(items: hasMore ? programs.sublist(0, limit) : programs, hasMore: hasMore);
  }

  @override
  Future<CoachProgram> getCoachProgram({required String coachId, required String id}) async {
    final rows = await _pool.execute(_getCoachProgram.toSql(), parameters: {'coachId': coachId, 'id': id});
    if (rows.isEmpty) throw NotFound(type: 'Library program', id: id);
    return CoachProgram.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<void> deleteCoachProgram({required String coachId, required String id}) async {
    await _pool.execute(_deleteCoachProgram.toSql(), parameters: {'coachId': coachId, 'id': id});
  }

  @override
  Future<List<CoachProgramHolder>> getCoachProgramHolders({required String coachId, required String id}) async {
    final rows = await _pool.execute(_listCoachProgramHolders.toSql(), parameters: {'coachId': coachId, 'id': id});
    return [for (final row in rows) CoachProgramHolder.fromRow(row.toColumnMap())];
  }

  @override
  Future<CoachSendContext?> getCoachSendContext({
    required String coachId,
    required String id,
    required String connectionId,
  }) async {
    final rows = await _pool.execute(
      _coachSendContext.toSql(),
      parameters: {'coachId': coachId, 'id': id, 'connectionId': connectionId},
    );
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => null,
      final row => (
        version: row['version'] as int,
        body: (row['body'] as Map).cast<String, dynamic>(),
        studentId: row['student_id'] as String?,
        existingProgramId: row['existing_id']?.toString(),
        studentBusy: row['on_something'] as bool,
      ),
    };
  }

  @override
  Future<Map<String, String>> matchExercisesForStudent({
    required List<String> ids,
    required String coachId,
    required String studentId,
  }) async {
    // two first logs of the same custom race to copy it, and the loser's retry finds
    // the winner's copy
    final rows = await _retryOnCreateRace(
      () => _pool.execute(
        _matchExercisesForStudent.toSql(),
        parameters: {'ids': ids, 'coachId': coachId, 'studentId': studentId},
      ),
    );
    return {for (final row in rows) row[0].toString(): row[1].toString()};
  }

  @override
  Future<String?> invitationProgram({required String token}) async {
    final rows = await _pool.execute(_invitationProgram.toSql(), parameters: {'tokenHash': TokenSecret.hash(token)});
    return rows.firstOrNull?.toColumnMap()['library_program_id']?.toString();
  }

  @override
  Future<void> attachInvitationProgram({
    required String coachId,
    required String invitationId,
    required String programId,
  }) async {
    final rows = await _pool.execute(
      _attachInvitationProgram.toSql(),
      parameters: {'coachId': coachId, 'invitationId': invitationId, 'programId': programId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Library program', id: programId);
  }

  @override
  Future<void> startProgram({required String userId, required String programId}) async {
    await _pool.execute(_startProgram.toSql(), parameters: {'userId': userId, 'programId': programId});
  }
}
