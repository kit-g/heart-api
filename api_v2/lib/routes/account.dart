import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<User> upsertAccount(final Request request) async {
  final user = request.user;
  final requestUser = User.fromJson(await request.json());
  if (user.id != requestUser.id) {
    throw const Forbidden(reason: 'You can only modify your own profile');
  }
  await request.profileService.upsertProfile(requestUser);
  return requestUser;
}
