import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/globals/globals.dart';
import 'package:relic/relic.dart';

Middleware authentication({bool Function(Request)? shouldAuthenticate}) {
  return (final Handler next) {
    return (final request) async {
      final needsAuth = shouldAuthenticate?.call(request) ?? true;
      if (!needsAuth) return next(request);

      final firebaseId = request.config.firebaseProjectId;

      if (request.headers.authorization case BearerAuthorizationHeader auth) {
        try {
          final user = await request.authenticator(firebaseId, auth.token);
          request.user = user;
          return next(request);
        } on AuthenticationError {
          return JsonResponse.unauthorized();
        } catch (e) {
          // todo log
          return JsonResponse.unauthorized();
        }
      }
      return JsonResponse.unauthorized();
    };
  };
}
