import 'package:heart/core/response.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';
import 'package:version/version.dart';

class _UpgradeRequired implements Model {
  const new();

  @override
  Map<String, dynamic> toMap() {
    return {'message': 'Please update the app to continue.'};
  }
}

/// Turns away a build below [minimal], and only that: the gate judges the
/// version a request states, so a request that states none, or one it cannot
/// read, goes through to the authentication behind it. Every app build sends
/// `x-app-version` once its headers are installed; the requests that arrive
/// without it are the first of a cold launch (the app's startup races its own
/// package lookup), deploy checks and people with curl — none of them an old
/// build, and each of them answered correctly by the gates that follow.
Middleware version({required String minimal, bool Function(Request)? shouldCheckVersion}) {
  return (Handler next) {
    return (request) {
      final supported = Version.parse(minimal);
      final needsCheck = shouldCheckVersion?.call(request) ?? true;
      return switch ((needsCheck, request.headers)) {
        (true, {'x-app-version': [String v]}) when _below(v, supported) => JsonResponse(
          426,
          body: const _UpgradeRequired(),
        ),
        _ => next(request),
      };
    };
  };
}

bool _below(String stated, Version supported) {
  try {
    return Version.parse(stated) < supported;
  } on FormatException {
    return false;
  }
}
