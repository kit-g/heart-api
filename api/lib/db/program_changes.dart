part of 'db.dart';

mixin _ProgramChanges on _DatabaseBase, _Programs implements ProgramChangeService {
  Never _changed(int revision) {
    throw Conflict(
      code: 'program_changed',
      reason: 'The other person changed this since you started.',
      payload: {'revision': revision},
    );
  }

  Future<void> _record(
    Session tx, {
    required String? changeId,
    required String programId,
    required String? sessionId,
    required String actorId,
    required String kind,
    required int revision,
    required Map<String, dynamic>? before,
    required Map<String, dynamic>? after,
    Map<String, dynamic>? links,
    bool stale = false,
  }) async {
    await tx.execute(
      _recordProgramChange.toSql(),
      parameters: {
        'id': changeId ?? uuidV7(),
        'programId': programId,
        'sessionId': sessionId,
        'actorId': actorId,
        'kind': kind,
        'revision': revision,
        'before': before == null ? null : jsonEncode(before),
        'after': after == null ? null : jsonEncode(after),
        'links': links == null ? null : jsonEncode(links),
        'stale': stale,
      },
    );
  }

  Future<Template> _readSession(Session tx, {required String userId, required String sessionId}) async {
    final rows = await tx.execute(_getTemplate.toSql(), parameters: {'userId': userId, 'templateId': sessionId});
    return Template.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<Template?> writeSession({
    required String ownerId,
    required String actorId,
    required String sessionId,
    required TemplateRequest body,
    String? programId,
    int? baseRevision,
    String? changeId,
    String kind = 'edit',
  }) async {
    return _pool.runTx<Template?>((tx) async {
      final locked = await tx.execute(
        _lockCopySession.toSql(),
        parameters: {'ownerId': ownerId, 'sessionId': sessionId, 'programId': programId},
      );
      final lock = locked.firstOrNull?.toColumnMap();
      if (lock == null) return null;
      final row = {
        ...lock,
        ...(await tx.execute(
          _copySessionStanding.toSql(),
          parameters: {'sessionId': sessionId, 'actorId': actorId, 'baseRevision': baseRevision, 'changeId': changeId},
        )).first.toColumnMap(),
      };
      if (row['replayed'] == true) return _readSession(tx, userId: ownerId, sessionId: sessionId);
      if (row['conflict'] == true) _changed(row['revision'] as int);

      final before = await _readSession(tx, userId: ownerId, sessionId: sessionId);
      await tx.execute(
        _replaceTemplate.toSql(),
        parameters: {
          'templateId': sessionId,
          'movesFolder': body.movesFolder,
          'movesProgram': false,
          'changesNote': body.changesNote,
          ...body.toParams(),
          'programId': row['program_id'].toString(),
          'joined': body.joined,
          'note': body.note,
        },
      );
      final bumped = await tx.execute(_bumpSessionRevision.toSql(), parameters: {'sessionId': sessionId});
      final after = await _readSession(tx, userId: ownerId, sessionId: sessionId);
      await _record(
        tx,
        changeId: changeId,
        programId: row['program_id'].toString(),
        sessionId: sessionId,
        actorId: actorId,
        kind: kind,
        revision: bumped.first[0]! as int,
        before: before.toMap(),
        after: after.toMap(),
        stale: baseRevision == null && kind == 'edit',
      );
      return after;
    });
  }

  @override
  Future<Template> restoreSession({
    required String ownerId,
    required String actorId,
    required String programId,
    required TemplateRequest body,
    Map<String, dynamic>? links,
    String kind = 'create',
  }) async {
    return _pool.runTx((tx) async {
      // it would answer the row there, and this would take over a template it never
      // was: of the student's own, of another program, or someone else's
      if (body.id case final String id) {
        final taken = await tx.execute(_templateIdTaken.toSql(), parameters: {'id': id});
        if (taken.isNotEmpty) throw const Forbidden(code: 'id_taken', reason: 'this id belongs to something else');
      }
      final saved = await tx.execute(
        _saveTemplate.toSql(),
        parameters: {
          'id': body.id,
          ...body.toParams(),
          'programId': programId,
          'joined': body.joined,
          'note': body.note,
        },
      );
      if (saved.isEmpty) throw NotFound(type: 'Program', id: programId);
      final sessionId = saved.first.toColumnMap()['id'].toString();
      final restored = await tx.execute(
        _restoreSessionLinks.toSql(),
        parameters: {
          'sessionId': sessionId,
          'ownerId': ownerId,
          'programId': programId,
          'workouts': [for (final id in (links?['workouts'] as List?) ?? const []) '$id'],
          'skips': [for (final id in (links?['skips'] as List?) ?? const []) '$id'],
        },
      );
      final after = await _readSession(tx, userId: ownerId, sessionId: sessionId);
      await _record(
        tx,
        changeId: null,
        programId: programId,
        sessionId: sessionId,
        actorId: actorId,
        kind: kind,
        revision: restored.first[0]! as int,
        before: null,
        after: after.toMap(),
      );
      return after;
    });
  }

  @override
  Future<bool> removeSession({
    required String ownerId,
    required String actorId,
    required String sessionId,
    String? programId,
    String kind = 'delete',
  }) async {
    return _pool.runTx((tx) async {
      final locked = await tx.execute(
        _lockCopySession.toSql(),
        parameters: {'ownerId': ownerId, 'sessionId': sessionId, 'programId': programId},
      );
      final lock = locked.firstOrNull?.toColumnMap();
      if (lock == null) return false;
      final row = {
        ...lock,
        ...(await tx.execute(
          _copySessionStanding.toSql(),
          parameters: {'sessionId': sessionId, 'actorId': actorId, 'baseRevision': null, 'changeId': null},
        )).first.toColumnMap(),
      };
      final before = await _readSession(tx, userId: ownerId, sessionId: sessionId);
      final linked = await tx.execute(_sessionLinks.toSql(), parameters: {'sessionId': sessionId, 'ownerId': ownerId});
      await tx.execute(_deleteSession.toSql(), parameters: {'sessionId': sessionId, 'ownerId': ownerId});
      await _record(
        tx,
        changeId: null,
        programId: row['program_id'].toString(),
        sessionId: sessionId,
        actorId: actorId,
        kind: kind,
        revision: (row['revision'] as int) + 1,
        before: before.toMap(),
        after: null,
        links: (linked.first[0]! as Map).cast<String, dynamic>(),
      );
      return true;
    });
  }

  @override
  Future<Program?> writeProgramFields({
    required String ownerId,
    required String actorId,
    required String programId,
    required Program program,
    int? baseRevision,
    String? changeId,
    String kind = 'edit',
  }) async {
    return _pool.runTx<Program?>((tx) async {
      final locked = await tx.execute(
        _lockCopy.toSql(),
        parameters: {'ownerId': ownerId, 'programId': programId},
      );
      if (locked.isEmpty) return null;
      final standing = await tx.execute(
        _copyStanding.toSql(),
        parameters: {'programId': programId, 'actorId': actorId, 'baseRevision': baseRevision, 'changeId': changeId},
      );
      final row = standing.first.toColumnMap();
      if (row['replayed'] == true) return _readProgram(tx, userId: ownerId, programId: programId);
      if (row['conflict'] == true) _changed(row['revision'] as int);

      final before = await _readProgram(tx, userId: ownerId, programId: programId);
      await tx.execute(
        _replaceProgram.toSql(),
        parameters: {
          'id': programId,
          'userId': ownerId,
          ..._programParams(program)..remove('source'),
          'archived': program.archived,
        },
      );
      final bumped = await tx.execute(_bumpProgramRevision.toSql(), parameters: {'programId': programId});
      final after = await _readProgram(tx, userId: ownerId, programId: programId);
      await _record(
        tx,
        changeId: changeId,
        programId: programId,
        sessionId: null,
        actorId: actorId,
        kind: kind,
        revision: bumped.first[0]! as int,
        before: before.toMap(),
        after: after.toMap(),
        stale: baseRevision == null && kind == 'edit',
      );
      return after;
    });
  }

  @override
  Future<List<ProgramChange>> getProgramChanges({
    required String ownerId,
    required String programId,
    String? since,
  }) async {
    final after = since == null ? null : ChangeCursor.parse(since);
    final rows = await _pool.execute(
      _listProgramChanges.toSql(),
      parameters: {'ownerId': ownerId, 'programId': programId, 'xid': after?.xid, 'changeId': after?.id},
    );
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        ProgramChange.fromRow(
          row,
          cursor: ChangeCursor(xid: row['xid_text'] as String, id: row['id'].toString()).toString(),
        ),
    ];
  }

  @override
  Future<({ProgramChange change, Map<String, dynamic>? links})?> getProgramChange({
    required String ownerId,
    required String programId,
    required String changeId,
  }) async {
    final rows = await _pool.execute(
      _getProgramChange.toSql(),
      parameters: {'ownerId': ownerId, 'programId': programId, 'changeId': changeId},
    );
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => null,
      final row => (change: ProgramChange.fromRow(row), links: (row['links'] as Map?)?.cast<String, dynamic>()),
    };
  }

  @override
  Future<CopyAccess> getCopyAccess({
    required String coachId,
    required String studentId,
    required String programId,
  }) async {
    final rows = await _pool.execute(
      _copyAccess.toSql(),
      parameters: {'coachId': coachId, 'studentId': studentId, 'programId': programId},
    );
    final row = rows.first.toColumnMap();
    return (readable: row['readable'] as bool, writable: row['writable'] as bool);
  }

  @override
  Future<List<Program>> getCopies({required String coachId, required String studentId}) async {
    final rows = await _pool.execute(_listCopies.toSql(), parameters: {'coachId': coachId, 'studentId': studentId});
    return [for (final row in rows) Program.fromRow(row.toColumnMap())];
  }

  @override
  Future<Iterable<ProgramMark>> getVisibleMarks({
    required String readerId,
    required String ownerId,
    required String programId,
  }) async {
    final rows = await _pool.execute(
      _listVisibleMarks.toSql(),
      parameters: {'readerId': readerId, 'ownerId': ownerId, 'programId': programId},
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

  @override
  Future<Map<String, String>> getCopyIds({required String ownerId, required String programId}) async {
    final rows = await _pool.execute(_getCopyIds.toSql(), parameters: {'ownerId': ownerId, 'programId': programId});
    return switch (rows.firstOrNull?[0]) {
      final Map ids => ids.cast<String, String>(),
      _ => const {},
    };
  }

  @override
  Future<void> setCopyVersion({
    required String ownerId,
    required String programId,
    required int version,
    required Map<String, String> ids,
  }) async {
    await _pool.execute(
      _setCopyVersion.toSql(),
      parameters: {'ownerId': ownerId, 'programId': programId, 'version': version, 'ids': jsonEncode(ids)},
    );
  }

  @override
  Future<String?> otherSideOf({required String actorId, required String programId}) async {
    final rows = await _pool.execute(_otherSideOf.toSql(), parameters: {'actorId': actorId, 'programId': programId});
    return rows.firstOrNull?[0] as String?;
  }

  @override
  Future<void> savePlan({
    required String userId,
    required String workoutId,
    required Map<String, dynamic> plan,
  }) async {
    final rows = await _pool.execute(
      _saveWorkoutPlan.toSql(),
      parameters: {'userId': userId, 'workoutId': workoutId, 'plan': jsonEncode(plan)},
    );
    if (rows.first[0] != true) throw NotFound(type: 'Workout', id: workoutId);
  }

  @override
  Future<Map<String, dynamic>?> getPlan({
    required String readerId,
    required String ownerId,
    required String workoutId,
  }) async {
    final rows = await _pool.execute(
      _getWorkoutPlan.toSql(),
      parameters: {'readerId': readerId, 'ownerId': ownerId, 'workoutId': workoutId},
    );
    return (rows.firstOrNull?[0] as Map?)?.cast<String, dynamic>();
  }
}
