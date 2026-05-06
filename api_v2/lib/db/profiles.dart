part of 'db.dart';

mixin _Profiles on _DatabaseBase implements ApiProfileService {
  @override
  Future<void> upsertProfile(User user) {
    return _pool.execute(
      _updateProfile.toSql(),
      parameters: {
        'id': user.id,
        'email': user.email,
        'username': user.displayName,
        'avatar': user.remoteAvatar,
      },
    );
  }

  @override
  Future<void> scheduleAccountDeletion({
    required String userId,
    required String scheduleArn,
    required DateTime scheduledAt,
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
  Future<void> undoAccountDeletion({required String userId}) {
    return _pool.execute(
      _undoAccountDeletion.toSql(),
      parameters: {'userId': userId},
    );
  }

  @override
  Future<void> deleteAccount({required String userId}) {
    return _pool.execute(
      _deleteAccount.toSql(),
      parameters: {'userId': userId},
    );
  }
}
