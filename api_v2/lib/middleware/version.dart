import 'package:heart/core/response.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';
import 'package:version/version.dart';

class _UpgradeRequired implements Model {
  const _UpgradeRequired();

  @override
  Map<String, dynamic> toMap() {
    return {'message': 'Please update the app to continue.'};
  }
}

Middleware version({required String minimal, bool Function(Request)? shouldCheckVersion}) {
  return (final Handler next) {
    return (final request) {
      final supported = Version.parse(minimal);
      final needsCheck = shouldCheckVersion?.call(request) ?? true;
      return switch ((needsCheck, request.headers)) {
        (false, _) => next(request),
        (true, {'x-app-version': [String v]}) when Version.parse(v) >= supported => next(request),
        _ => JsonResponse(426, body: const _UpgradeRequired()),
      };
    };
  };
}
