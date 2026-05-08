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
  Future<void> deleteAccount({required String userId}) {
    return _pool.execute(
      _deleteAccount.toSql(),
      parameters: {'userId': userId},
    );
  }
}
