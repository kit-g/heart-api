import 'package:heart_models/heart_models.dart';

abstract class ApiException implements Model {
  int get statusCode;
}

class NotFound implements ApiException {
  final String type;
  final String id;

  const NotFound({
    required this.type,
    required this.id,
  });

  @override
  String toString() {
    return '$type #$id not found';
  }

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'not found', 'message': toString()};
  }

  @override
  int get statusCode => 404;
}

class NoContent implements ApiException {
  const NoContent();

  @override
  Map<String, dynamic> toMap() {
    throw UnimplementedError(); // no body
  }

  @override
  int get statusCode => 204;
}

class BadRequest implements ApiException {
  final String reason;
  final Map? payload;

  const BadRequest({
    required this.reason,
    this.payload,
  });

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'bad request', 'reason': reason};
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

  const Forbidden({required this.reason});

  @override
  int get statusCode => 403;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'forbidden',
      'reason': reason,
    };
  }
}

class UnsupportedMediaType implements ApiException {
  final String reason;

  const UnsupportedMediaType({required this.reason});

  @override
  int get statusCode => 415;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'unsupported media type',
      'reason': reason,
    };
  }

  @override
  String toString() => '$runtimeType: $reason';
}

class NotImplemented implements ApiException {
  final String reason;

  const NotImplemented({required this.reason});

  @override
  int get statusCode => 501;

  @override
  Map<String, dynamic> toMap() {
    return {
      'error': 'not implemented',
      'reason': reason,
    };
  }
}
