import 'dart:convert';
import 'dart:typed_data';

import 'package:heart/models/model.dart';
import 'package:relic/relic.dart';

class _NotFound implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'not found'};
  }
}

class _ServerError implements Model {
  @override
  Map<String, dynamic> toMap() {
    return {'error': 'server error'};
  }
}

class JsonResponse<T extends Model> extends Response {
  JsonResponse(super.statusCode, {T? body, Headers? headers})
    : super(
        body: switch (body) {
          T m => Body.fromString(jsonEncode(m.toMap()), mimeType: .json),
          null => Body.fromData(Uint8List(0), mimeType: .json),
        },
      );

  JsonResponse.ok({T? body, Headers? headers}) : this(200, body: body, headers: headers);

  JsonResponse.unauthorized({T? body, Headers? headers}) : this(401, body: body, headers: headers);

  JsonResponse.forbidden({T? body, Headers? headers}) : this(403, body: body, headers: headers);

  JsonResponse.notFound({T? body, Headers? headers})
    : this(
        404,
        body: body ?? _NotFound() as T,
        headers: headers,
      );

  JsonResponse.serverError({T? body, Headers? headers})
    : this(
        500,
        body: body ?? _ServerError() as T,
        headers: headers,
      );
}

typedef ModelHandler = Future<Model> Function(Request);
