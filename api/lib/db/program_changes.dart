part of 'db.dart';

mixin _ProgramChanges on _DatabaseBase, _Programs implements ProgramChangeService {
  Never _changed(int revision) {
    throw Conflict(
      code: 'program_changed',
      reason: 'The other person changed this since you started.',
      payload: {'revision': revision},
    );
  }

  /// A snapshot outlives the account of whoever it names, so it keeps their words and
  /// not who they were: the change's actor says that, and goes when they do.
  static const _identities = {'assignedBy', 'coachId', 'coachName'};

  String? _snapshot(Map<String, dynamic>? state) {
    return switch (state) {
      null => null,
      final state => jsonEncode({...state}..removeWhere((key, _) => _identities.contains(key))),
    };
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
        'before': _snapshot(before),
        'after': _snapshot(after),
        'links': switch (links) {
          null => null,
          final links => jsonEncode(links),
        },
        'stale': stale,
      },
    );
  }

  Future<Template> _readSession(Session tx, {required String userId, required String sessionId}) async {
    final rows = await tx.execute(_getTemplate.toSql(), parameters: {'userId': userId, 'templateId': sessionId});
    return Template.fromRow(rows.first.toColumnMap());
  }

  /// What a session, or the program's own fields, say: the same before and after a
  /// write means it changed nothing.
  Future<String?> _content(Session tx, {String? sessionId, String? programId}) async {
    final rows = await switch (sessionId) {
      final String id => tx.execute(_sessionContent.toSql(), parameters: {'sessionId': id}),
      null => tx.execute(_programContent.toSql(), parameters: {'programId': programId}),
    };
    return rows.firstOrNull?[0] as String?;
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
    try {
      return await _pool.runTx<Template?>((tx) async {
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
            parameters: {
              'sessionId': sessionId,
              'actorId': actorId,
              'baseRevision': baseRevision,
              'changeId': changeId,
            },
          )).first.toColumnMap(),
        };
        if (row['replayed'] == true) return _readSession(tx, userId: ownerId, sessionId: sessionId);
        if (row['conflict'] == true) _changed(row['revision'] as int);

        final before = await _readSession(tx, userId: ownerId, sessionId: sessionId);
        final content = await _content(tx, sessionId: sessionId);
        final replaced = await tx.execute(
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
        // the session is held and there, so only the folder can have refused it
        if (replaced.isEmpty) throw NotFound(type: 'TemplateFolder', id: body.folderId ?? '');
        // nothing changed, so there's nothing for the other person to be up against
        if (await _content(tx, sessionId: sessionId) == content) return before;
        final bumped = await tx.execute(
          _bumpSessionRevision.toSql(),
          parameters: {'sessionId': sessionId, 'actorId': actorId},
        );
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
    } on ServerException catch (e) {
      _rethrowClientIdCollision(e);
    }
  }

  @override
  Future<Template> restoreSession({
    required String ownerId,
    required String actorId,
    required String programId,
    required TemplateRequest body,
    Map<String, dynamic>? links,
    int? baseRevision,
    String? changeId,
    String kind = 'create',
  }) async {
    try {
      return await _pool.runTx((tx) async {
        if (body.id case final String id) {
          // it would answer the row there, and this would take over a template it never
          // was: of the student's own, of another program, or someone else's
          final taken = await tx.execute(_templateIdTaken.toSql(), parameters: {'id': id});
          if (taken.isNotEmpty) throw const Forbidden(code: 'id_taken', reason: 'this id belongs to something else');
          // a deletion since the base is someone else changing it, and leaves no
          // session for the usual check to read
          if (baseRevision != null) {
            final gone = await tx.execute(
              _goneSessionConflict.toSql(),
              parameters: {'programId': programId, 'sessionId': id, 'baseRevision': baseRevision, 'actorId': actorId},
            );
            if (gone.first[0] case final int revision) _changed(revision);
          }
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
        // a program not the owner's trips its foreign key, so only the folder refuses
        if (saved.isEmpty) throw NotFound(type: 'TemplateFolder', id: body.folderId ?? '');
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
          changeId: changeId,
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
    } on ServerException catch (e) {
      // two put-backs of one session, both past the check before either committed
      _rethrowClientIdCollision(e);
    }
  }

  @override
  Future<String?> removeSession({
    required String ownerId,
    required String actorId,
    required String sessionId,
    String? programId,
    int? baseRevision,
    String kind = 'delete',
  }) async {
    return _pool.runTx((tx) async {
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
          parameters: {'sessionId': sessionId, 'actorId': actorId, 'baseRevision': baseRevision, 'changeId': null},
        )).first.toColumnMap(),
      };
      if (row['conflict'] == true) _changed(row['revision'] as int);
      final before = await _readSession(tx, userId: ownerId, sessionId: sessionId);
      final linked = await tx.execute(_sessionLinks.toSql(), parameters: {'sessionId': sessionId, 'ownerId': ownerId});
      await tx.execute(_deleteSession.toSql(), parameters: {'sessionId': sessionId, 'ownerId': ownerId});
      final program = row['program_id'].toString();
      await _record(
        tx,
        changeId: null,
        programId: program,
        sessionId: sessionId,
        actorId: actorId,
        kind: kind,
        revision: (row['revision'] as int) + 1,
        before: before.toMap(),
        after: null,
        links: (linked.first[0]! as Map).cast<String, dynamic>(),
      );
      return program;
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
      final content = await _content(tx, programId: programId);
      await tx.execute(
        _replaceProgram.toSql(),
        parameters: {
          'id': programId,
          'userId': ownerId,
          ..._programParams(program)..remove('source'),
          'archived': program.archived,
        },
      );
      // nothing changed, so there's nothing for the other person to be up against
      if (await _content(tx, programId: programId) == content) return before;
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
  Future<Page<ProgramChange>> getProgramChanges({
    required String ownerId,
    required String programId,
    String? since,
    String? readerId,
    bool assistant = false,
  }) async {
    final after = switch (since) {
      null => null,
      final since => ChangeCursor.parse(since),
    };
    final rows = await _pool.execute(
      _listProgramChanges.toSql(),
      parameters: {
        'ownerId': ownerId,
        'programId': programId,
        'xid': after?.xid,
        'changeId': after?.id,
        'readerId': readerId,
        'assistant': assistant,
      },
    );
    final columns = [for (final row in rows) row.toColumnMap()];
    if (columns.first['owned'] != true) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
    if (columns.first['readable'] != true) {
      throw const Forbidden(reason: 'You do not have permission to read this program.');
    }
    if (columns.first['stale_cursor'] == true) {
      throw const BadRequest(
        code: 'stale_cursor',
        reason: 'this cursor is from before the database moved; start again without since',
      );
    }
    final changes = [
      // the check's row stands alone when there's nothing to report
      for (final row in columns)
        if (row['id'] != null)
          ProgramChange.fromRow(
            row,
            cursor: ChangeCursor(xid: row['xid_text'] as String, id: row['id'].toString()).toString(),
          ),
    ];
    return Page(items: changes.take(_programChangesPage).toList(), hasMore: changes.length > _programChangesPage);
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
      parameters: {'coachId': coachId, 'studentId': studentId, 'programId': programId, 'assistant': false},
    );
    final row = rows.first.toColumnMap();
    return (readable: row['readable'] as bool, writable: row['writable'] as bool);
  }

  @override
  Future<CopyRead> readCopy({
    required String coachId,
    required String studentId,
    required String programId,
    bool assistant = false,
  }) {
    // one snapshot, taken by the check: what it allowed is what the reads see
    return _pool.runTx(
      (tx) async {
        final access = (await tx.execute(
          _copyAccess.toSql(),
          parameters: {'coachId': coachId, 'studentId': studentId, 'programId': programId, 'assistant': assistant},
        )).first.toColumnMap();
        if (access['sent'] != true) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
        if (access['readable'] != true) {
          throw const Forbidden(reason: 'You do not have permission to read this program.');
        }
        final program = await _readProgram(tx, userId: studentId, programId: programId);
        final sessions = <Template>[];
        for (final id in program.sessions) {
          final rows = await tx.execute(_getTemplate.toSql(), parameters: {'userId': studentId, 'templateId': id});
          if (rows.isEmpty) throw NotFound(type: 'Template', id: id);
          sessions.add(Template.fromRow(rows.first.toColumnMap()));
        }
        final actions = await tx.execute(
          _listProgramActions.toSql(),
          parameters: {'userId': studentId, 'programId': programId},
        );
        return (
          program: program,
          sessions: sessions,
          actions: [for (final row in actions) ProgramAction.fromRow(row.toColumnMap())],
          marks: await _visibleMarks(
            tx,
            readerId: coachId,
            ownerId: studentId,
            programId: programId,
            assistant: assistant,
          ),
        );
      },
      settings: TransactionSettings(isolationLevel: IsolationLevel.repeatableRead, accessMode: AccessMode.readOnly),
    );
  }

  @override
  Future<List<Program>> getCopies({required String coachId, required String studentId, bool assistant = false}) async {
    final rows = await _pool.execute(
      _listCopies.toSql(),
      parameters: {'coachId': coachId, 'studentId': studentId, 'assistant': assistant},
    );
    return [for (final row in rows) Program.fromRow(row.toColumnMap())];
  }

  @override
  Future<Iterable<ProgramMark>> getVisibleMarks({
    required String readerId,
    required String ownerId,
    required String programId,
    bool assistant = false,
  }) {
    return _visibleMarks(_pool, readerId: readerId, ownerId: ownerId, programId: programId, assistant: assistant);
  }

  Future<List<ProgramMark>> _visibleMarks(
    Session session, {
    required String readerId,
    required String ownerId,
    required String programId,
    required bool assistant,
  }) async {
    final rows = await session.execute(
      _listVisibleMarks.toSql(),
      parameters: {'readerId': readerId, 'ownerId': ownerId, 'programId': programId, 'assistant': assistant},
    );
    return [
      for (final row in rows)
        if (row.toColumnMap() case final map)
          ProgramMark(
            templateId: map['template_id']?.toString(),
            at: map['at'] as DateTime,
            isWorkout: map['is_workout'] as bool,
          ),
    ];
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
  Future<bool> canLogFor({required String coachId, required String studentId}) async {
    final rows = await _pool.execute(_coachCanLog.toSql(), parameters: {'coachId': coachId, 'studentId': studentId});
    return rows.first[0]! as bool;
  }

  @override
  Future<void> savePlan({
    required String userId,
    required String workoutId,
    required Map<String, dynamic> plan,
    String? loggedBy,
  }) async {
    final rows = await _pool.execute(
      _saveWorkoutPlan.toSql(),
      parameters: {'userId': userId, 'workoutId': workoutId, 'plan': jsonEncode(plan), 'loggedBy': loggedBy},
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
