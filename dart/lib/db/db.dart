library;

import 'package:aws_client/dynamo_document.dart';
import 'package:heart_models/heart_models.dart';

part 'charts.dart';

abstract class _DatabaseBase {
  DocumentClient get client;

  const _DatabaseBase();
}

class Database extends _DatabaseBase with _Charts implements ChartPreferenceService {
  @override
  final DocumentClient client;
  @override
  final String table;

  const Database({
    required this.client,
    required this.table,
  });
}
