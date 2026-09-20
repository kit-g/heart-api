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
