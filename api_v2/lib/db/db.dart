library;

import 'package:aws_client/dynamo_document.dart';
import 'package:heart/models/connections.dart';
import 'package:heart_models/heart_models.dart';

part 'charts.dart';
part 'connections.dart';

abstract class _DatabaseBase {
  DocumentClient get _client;

  const _DatabaseBase();
}

class Database extends _DatabaseBase with _Charts, _Connections implements ChartPreferenceService, ConnectionsService {
  @override
  final DocumentClient _client;
  @override
  final String table;

  const Database({
    required DocumentClient client,
    required this.table,
  }) : _client = client;
}
