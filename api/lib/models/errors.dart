import 'package:heart_models/heart_models.dart';

abstract class ApiException implements Model {
  int get statusCode;

  /// A stable, machine-readable identifier for this failure, emitted as `code`
  /// in every error body. Unlike the human `reason`/`message`, it is never
  /// reworded, so a client can branch on it — e.g. tell the `goal_limit`
  /// rejection apart from any other 400 without matching prose. It always
  /// defaults to the category (`bad_request`, `not_found`, …); specific
  /// failures override it.
  String get code;
}

class NotFound implements ApiException {
  final String type;
  final String id;
  @override
  final String code;

  const new({
    required this.type,
    required this.id,
    this.code = 'not_found',
  });

  @override
  String toString() {
    return '$type #$id not found';
  }

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'not found', 'code': code, 'message': toString()};
  }

  @override
  int get statusCode => 404;
}

class NoContent implements ApiException {
  const new();

  @override
  String get code => 'no_content';

  @override
  Map<String, dynamic> toMap() {
    throw UnimplementedError(); // no body
  }

  @override
  int get statusCode => 204;
}

class BadRequest implements ApiException {
  final String reason;
  @override
  final String code;
  final Map? payload;

  const new({
    required this.reason,
    this.code = 'bad_request',
    this.payload,
  });

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'bad request', 'code': code, 'reason': reason};
  }

  @override
  int get statusCode => 400;

  @override
  String toString() {
    if (payload != null) {
      return '$runtimeType: $reason, $payload';
    }
    return '$runtimeType: $reason';
  }
}

class Forbidden implements ApiException {
  final String reason;
  @override
  final String code;

  const new({required this.reason, this.code = 'forbidden'});

  @override
  int get statusCode => 403;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'forbidden',
      'code': code,
      'reason': reason,
    };
  }
}

class UnsupportedMediaType implements ApiException {
  final String reason;
  @override
  final String code;

  const new({required this.reason, this.code = 'unsupported_media_type'});

  @override
  int get statusCode => 415;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'unsupported media type',
      'code': code,
      'reason': reason,
    };
  }

  @override
  String toString() => '$runtimeType: $reason';
}

class NotImplemented implements ApiException {
  final String reason;
  @override
  final String code;

  const new({required this.reason, this.code = 'not_implemented'});

  @override
  int get statusCode => 501;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'not implemented',
      'code': code,
      'reason': reason,
    };
  }
}

class Unauthorized implements ApiException {
  final String reason;
  @override
  final String code;

  const new({required this.reason, this.code = 'unauthorized'});

  @override
  int get statusCode => 401;

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'unauthorized', 'code': code, 'reason': reason};
  }
}

class TooManyRequests implements ApiException {
  final String reason;

  /// Whole seconds until the window that ran out restarts; the `Retry-After`.
  final int retryAfter;

  @override
  final String code;

  const new({required this.reason, required this.retryAfter, this.code = 'rate_limited'});

  @override
  int get statusCode => 429;

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'too many requests', 'code': code, 'reason': reason, 'retryAfter': retryAfter};
  }
}
