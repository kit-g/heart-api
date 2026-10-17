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
    return AnomaliesQuery._(
      status: switch (req.url.queryParameters['status']) {
        null => null,
        final raw => _status(raw),
      },
      cursor: page.cursor,
      limit: page.limit,
    );
  }

  static AnomalyStatus _status(String raw) {
    try {
      return AnomalyStatus.fromString(raw);
    } on ArgumentError {
      throw BadRequest(reason: 'status must be pending, valid or invalid: $raw');
    }
  }
}

/// `PUT /anomalies/:anomalyId`: `{status: valid|invalid}`, what the user made
/// of it. Deciding is final; editing the entry is the way to change it.
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
