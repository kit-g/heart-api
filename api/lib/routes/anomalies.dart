import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// The user's suspicious entries, newest first; `?status=` for one kind.
Future<Paginated<Anomaly>> getAnomalies(Request req) async {
  final query = AnomaliesQuery.fromRequest(req);
  final page = await req.anomalyService.getAnomalies(
    userId: req.userId,
    status: query.status,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<Anomaly>.from(page, itemsKey: 'anomalies', cursorOf: (anomaly) => anomaly.id);
}

Future<Anomaly> resolveAnomaly(Request req) => resolveAnomalyById(req, req.rawPathParameters[#anomalyId]!);

/// What the user made of one anomaly: valid, or invalid.
Future<Anomaly> resolveAnomalyById(Request req, String anomalyId) async {
  if (!isUuidV7(anomalyId)) throw NotFound(type: 'Anomaly', id: anomalyId);
  final input = await AnomalyResolveIn.fromRequest(req);
  return await req.anomalyService.resolveAnomaly(userId: req.userId, anomalyId: anomalyId, status: input.status) ??
      (throw NotFound(type: 'Anomaly', id: anomalyId));
}
