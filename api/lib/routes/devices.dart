import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> registerDevice(Request req) async {
  final input = await DeviceRegisterIn.fromRequest(req);
  await req.deviceService.registerDevice(
    profileId: req.userId,
    platform: input.platform,
    token: input.token,
    locale: input.locale,
    settings: input.settings,
    utcOffsetMinutes: input.utcOffsetMinutes,
  );
  throw const NoContent();
}

/// The app stops getting the caller's pushes on this device, on sign-out or when
/// pushes are turned off. One that isn't registered is already stopped.
Future<Model> unregisterDevice(Request req) async {
  final input = await DeviceUnregisterIn.fromRequest(req);
  await req.deviceService.unregisterDevice(profileId: req.userId, token: input.token);
  throw const NoContent();
}
