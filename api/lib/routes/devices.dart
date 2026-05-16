import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> registerDevice(final Request req) async {
  final body = await req.json();
  final platformRaw = body['platform'] as String?;
  final token = body['token'] as String?;
  final settings = (body['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

  if (platformRaw == null || platformRaw.isEmpty) {
    throw const BadRequest(reason: 'platform is required');
  }

  if (token == null || token.isEmpty) {
    throw const BadRequest(reason: 'token is required');
  }

  final DevicePlatform platform;
  try {
    platform = DevicePlatform.fromString(platformRaw);
  } on ArgumentError {
    throw const BadRequest(reason: 'platform must be one of: ios, android, web');
  }

  await req.deviceService.registerDevice(
    profileId: req.userId,
    platform: platform,
    token: token,
    settings: settings,
  );

  throw const NoContent();
}
