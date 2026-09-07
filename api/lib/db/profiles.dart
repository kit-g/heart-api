part of 'db.dart';

mixin _Profiles on _DatabaseBase implements ApiProfileService {
  @override
  Future<User> upsertProfile(User user) async {
    final rows = await _pool.execute(
      _updateAccount.toSql(),
      parameters: {
        'id': user.id,
        'email': user.email,
        'username': user.displayName,
        'avatar': user.remoteAvatar,
        'settings': jsonEncode(user.settings.toMap()),
      },
    );
    return User.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<void> scheduleAccountDeletion({
    required String userId,
    String? scheduleArn,
    DateTime? scheduledAt,
  }) {
    return _pool.execute(
      _scheduleAccountDeletion.toSql(),
      parameters: {
        'userId': userId,
        'schedule': scheduleArn,
        'scheduledAt': scheduledAt,
      },
    );
  }

  @override
  Future<User> undoAccountDeletion({required String userId}) async {
    final rows = await _pool.execute(
      _undoAccountDeletion.toSql(),
      parameters: {'userId': userId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Profile', id: userId);
    return User.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<User> updateAvatarUrl({required String userId, String? avatarUrl}) async {
    final rows = await _pool.execute(
      _updateAvatarUrl.toSql(),
      parameters: {'userId': userId, 'avatarUrl': avatarUrl},
    );
    if (rows.isEmpty) throw NotFound(type: 'Profile', id: userId);
    return User.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<void> deleteAccount({required String userId}) {
    return _pool.execute(
      _deleteAccount.toSql(),
      parameters: {'userId': userId},
    );
  }

  @override
  Future<AccountSummary> getAccountSummary(String userId) async {
    final rows = await _pool.execute(
      _accountSummary.toSql(),
      parameters: {'userId': userId},
    );
    // The query cross-joins ten one-row CTEs, so it returns exactly one row for
    // any user id — an unknown one included, with every count zero. There is no
    // empty-result branch to handle, and deliberately no NotFound: "you own
    // nothing" is a true answer, not a missing account.
    final row = rows.first.toColumnMap();

    // snake_case column aliases stay in this layer; the model is camelCase.
    CollectionSummary of(String column) {
      return CollectionSummary(
        count: row['${column}_count'] as int,
        latestId: row['${column}_latest'] as String?,
      );
    }

    return AccountSummary(
      collections: <ExportableCollection, CollectionSummary>{
        .customExercises: of('custom_exercises'),
        .exercisePreferences: of('exercise_preferences'),
        .templateFolders: of('template_folders'),
        .templates: of('templates'),
        .templateShares: of('template_shares'),
        .workouts: of('workouts'),
        .workoutImages: of('workout_images'),
        .goals: of('goals'),
        .comments: of('comments'),
        .connections: of('connections'),
      },
    );
  }
}
