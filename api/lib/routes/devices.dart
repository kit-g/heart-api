import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> registerDevice(final Request req) async {
  final input = await DeviceRegisterIn.fromRequest(req);
  await req.deviceService.registerDevice(
    profileId: req.userId,
    platform: input.platform,
    token: input.token,
    locale: input.locale,
    settings: input.settings,
  );
  throw const NoContent();
}
