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

class _ServerError implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'server error', 'code': 'server_error'};
  }
}

class JsonResponse<T extends Model> extends Response {
  new(super.statusCode, {T? body, Headers? headers})
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
