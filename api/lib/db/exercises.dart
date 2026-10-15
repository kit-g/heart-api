part of 'db.dart';

mixin _Exercises on _DatabaseBase implements ExerciseService {
  @override
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale, bool owned = false}) async {
    final rows = await _pool.execute(
      _listExercises.toSql(),
      parameters: {
        'userId': userId,
        'locale': locale,
        // regional locales (es_ES) fall back to their base language (es)
        // before the master columns; see the tb join in _listExercises
        'baseLocale': locale?.split('_').first,
        'owned': owned,
      },
    );
    final row = rows.first.toColumnMap();
    return {
      'exercises': row['exercises'] as List? ?? const [],
      'glossary': row['glossary'] as Map? ?? const {},
    };
  }

  @override
  Future<Map<String, dynamic>> createExercise({
    required String userId,
    String? id,
    required String name,
    required String category,
    required String target,
    String? instructions,
    String? pattern,
  }) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createExercise.toSql(),
          parameters: {
            'userId': userId,
            'id': id,
            'name': name,
            'category': category,
            'target': target,
            'instructions': instructions,
            'pattern': pattern,
          },
        ),
      );
      // Empty means the pre-check missed (the id belongs to someone else) and
      // the insert itself was never attempted at all — impossible with the
      // current statement, but the exception path below is what actually
      // handles that case; this is just the type-safe fallback.
      if (rows.isEmpty) throw _idTaken;
      // `created` rides along in the row map — routes/exercises.dart strips it
      // before serializing and uses it to pick 200 vs 201.
      return rows.first.toColumnMap();
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<Map<String, dynamic>> updateExercise({
    required String userId,
    required String exerciseId,
    String? category,
    String? target,
    String? instructions,
    bool? archived,
    ({String? value})? pattern,
  }) async {
    final rows = await _pool.execute(
      _updateExercise.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': exerciseId,
        'category': category,
        'target': target,
        'instructions': instructions,
        'archived': archived,
        'setsPattern': pattern != null,
        'pattern': pattern?.value,
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Exercise', id: exerciseId);
    return rows.first.toColumnMap();
  }

  @override
  Future<void> setExerciseMedia({
    required String key,
    required Map<String, dynamic> asset,
    required Map<String, dynamic> thumbnail,
  }) async {
    final rows = await _pool.execute(
      _setExerciseMedia.toSql(),
      parameters: {
        'key': key,
        'asset': jsonEncode(asset),
        'thumbnail': jsonEncode(thumbnail),
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Exercise', id: key);
  }

  @override
  Future<ExerciseMoveReport> moveExerciseHistory({
    required String userId,
    required String sourceId,
    required String targetId,
    required bool dryRun,
  }) async {
    try {
      final rows = await _pool.execute(
        _moveExerciseHistory.toSql(),
        parameters: {
          'userId': userId,
          'sourceId': sourceId,
          'targetId': targetId,
          'dryRun': dryRun,
        },
      );
      return ExerciseMoveReport.fromRow(
        rows.first.toColumnMap(),
        sourceId: sourceId,
        targetId: targetId,
        dryRun: dryRun,
      );
    } on ServerException catch (e) {
      switch (e) {
        // no_data_found, carrying the id the user may not reference — missing or
        // someone else's custom, one answer for both (see `_saveExercisePreference`)
        case ServerException(code: 'P0002', detail: final String id):
          throw NotFound(type: 'Exercise', id: id, code: 'unknown_exercise');
        // invalid_parameter_value: the function's own source = target guard; the
        // route refuses it earlier, this keeps any other caller at a 400
        case ServerException(code: '22023'):
          throw const BadRequest(code: 'same_exercise', reason: 'source and target are the same exercise');
        // datatype_mismatch: the target's category keeps sets in other columns
        // than the source's, so the moved sets would hold values nothing reads
        case ServerException(code: '42804', detail: final String detail):
          throw BadRequest(
            code: 'incompatible_exercise',
            reason: "the target's sets cannot hold the source's: $detail",
          );
        default:
          rethrow;
      }
    }
  }
}
