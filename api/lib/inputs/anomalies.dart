part of 'inputs.dart';

/// `GET /anomalies` and `/me/anomalies`: `?status=pending|valid|invalid` for
/// one kind, `?cursor=&limit=` for a page.
class AnomaliesQuery {
  final AnomalyStatus? status;
  final String? cursor;
  final int limit;

  const new _({required this.status, required this.cursor, required this.limit});

  static AnomaliesQuery fromRequest(Request req) {
    final page = PageQuery.fromRequest(req, defaultLimit: 30, maxLimit: 100);
    if (page.cursor case final cursor? when !isUuidV7(cursor)) {
      throw const BadRequest(reason: 'cursor must be the one the previous page returned');
    }
    final q = req.url.queryParameters;
    return AnomaliesQuery._(
      status: switch (q.stringOrNull('status')) {
        null => null,
        _ => q.parsed('status', AnomalyStatus.fromString),
      },
      cursor: page.cursor,
      limit: page.limit,
    );
  }
}

/// `PUT /anomalies/:anomalyId`: `{status: valid|invalid}`, what the user made
/// of it, replacing what it made of it before.
class AnomalyResolveIn {
  final AnomalyStatus status;

  const new _(this.status);

  static Future<AnomalyResolveIn> fromRequest(Request req) async {
    final json = await req.json();
    return AnomalyResolveIn._(switch (json['status']) {
      'valid' => .valid,
      'invalid' => .invalid,
      _ => throw const BadRequest(code: 'invalid_status', reason: 'status must be valid or invalid'),
    });
  }
}
