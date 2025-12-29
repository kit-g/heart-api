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
