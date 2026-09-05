import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/models/errors.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('AuthenticationMiddleware');

Middleware authentication({bool Function(Request)? shouldAuthenticate}) {
  return (Handler next) {
    return (request) async {
      final needsAuth = shouldAuthenticate?.call(request) ?? true;
      if (!needsAuth) return next(request);

      final firebaseId = request.config.firebaseProjectId;

      if (request.headers.authorization case BearerAuthorizationHeader auth) {
        try {
          final user = await request.authenticator(firebaseId, auth.token);
          request.user = user;
          return await next(request);
        } on AnonymousAccountError {
          return JsonResponse.forbidden(
            body: const Forbidden(
              code: 'anonymous_account',
              reason: 'Anonymous Firebase accounts cannot access this endpoint. Sign in to continue.',
            ),
          );
        } on AuthenticationError {
          return JsonResponse.unauthorized();
        } catch (e, st) {
          _logger.severe('Unknown error', e, st);
          return JsonResponse.unauthorized();
        }
      }
      return JsonResponse.unauthorized();
    };
  };
}
