import 'dart:convert';
import 'dart:typed_data';

import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

class _NotFound implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'not found', 'code': 'not_found'};
  }
}

/// The router's own 404: the request matched no route at all, so no handler
/// ever ran. Kept distinct from [_NotFound] — which a handler returns when a
/// route exists but the row behind it does not — because the two mean opposite
/// things to a caller. A missing row is a normal outcome worth no one's
/// attention; a missing route is always a client built against an endpoint this
/// API does not have, and is never expected.
class _NoSuchRoute implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'no such route', 'code': 'route_not_found'};
  }
}

/// The 405 this API composes for itself. Relic will produce one too, but it
/// does so from the router's own lookup — before any handler exists to wrap —
/// so that one never reaches the middleware chain and carries neither CORS
/// headers nor a JSON body. `buildApp` registers the verbs a path does not
/// serve so this is returned instead.
class _MethodNotAllowed implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'method not allowed', 'code': 'method_not_allowed'};
  }
}

class _ServerError implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'server error', 'code': 'server_error'};
  }
}

class JsonResponse<T extends Model> extends Response {
  new(super.statusCode, {T? body, super.headers})
    : super(
        body: switch (body) {
          T m => Body.fromString(jsonEncode(m.toMap()), mimeType: .json),
          null => Body.fromData(Uint8List(0), mimeType: .json),
        },
      );

  new ok({T? body, Headers? headers}) : this(200, body: body, headers: headers);

  new noContent({Headers? headers}) : this(204, headers: headers);

  new unauthorized({T? body, Headers? headers}) : this(401, body: body, headers: headers);

  new forbidden({T? body, Headers? headers}) : this(403, body: body, headers: headers);

  new notFound({T? body, Headers? headers})
    : this(
        404,
        body: body ?? _NotFound() as T,
        headers: headers,
      );

  /// The 405 for a path this API serves under some other verb — see
  /// [_MethodNotAllowed]. [allowed] becomes the `Allow` header, which is
  /// required of a 405 and is the only place the caller learns what it can
  /// use instead.
  new methodNotAllowed({required Set<Method> allowed})
    : this(
        405,
        body: _MethodNotAllowed() as T,
        headers: Headers.build((headers) => headers.allow = allowed),
      );

  /// The 404 for a path/verb that matches no route — see [_NoSuchRoute].
  new noSuchRoute({Headers? headers})
    : this(
        404,
        body: _NoSuchRoute() as T,
        headers: headers,
      );

  new serverError({T? body, Headers? headers})
    : this(
        500,
        body: body ?? _ServerError() as T,
        headers: headers,
      );

  new notImplemented({T? body, Headers? headers})
    : this(
        501,
        body: body ?? _ServerError() as T,
        headers: headers,
      );
}

typedef ModelHandler = Future<Model?> Function(Request);
