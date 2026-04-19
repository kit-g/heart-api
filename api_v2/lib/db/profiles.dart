part of 'db.dart';

mixin _Profiles on _DatabaseBase implements ApiProfileService {
  @override
  Future<void> upsertProfile(User user) async {
    await _pool.execute(
      _updateProfile.toSql(),
      parameters: {
        'id': user.id,
        'email': user.email,
        'username': user.displayName,
        'avatar': user.remoteAvatar,
      },
    );
  }
}
