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

  const BadRequest({required this.reason});

  @override
  Map<String, dynamic> toMap() {
    return {'error': 'bad request', 'reason': reason};
  }

  @override
  int get statusCode => 400;
}
