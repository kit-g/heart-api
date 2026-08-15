part of 'inputs.dart';

class ChartPreferenceSaveIn {
  final ChartPreference preference;

  const new _({required this.preference});

  /// Accepts the wire shape existing clients already send (`type`, optional
  /// `data` object or JSON-encoded string, optional `id`) — the same shape
  /// [ChartPreference.fromRow] happens to parse — but validates it here
  /// instead of coupling the endpoint to the DB-row parser.
  static Future<ChartPreferenceSaveIn> fromRequest(Request req) async {
    final json = await req.json();
    return ChartPreferenceSaveIn._(
      preference: ChartPreference.create(
        id: json['id']?.toString(),
        type: json.parsed('type', ChartPreferenceType.fromString),
        data: switch (json['data']) {
          null => null,
          Map m => m.cast<String, dynamic>(),
          String raw => switch (jsonDecode(raw)) {
            Map m => m.cast<String, dynamic>(),
            _ => throw const BadRequest(reason: 'data must be an object'),
          },
          _ => throw const BadRequest(reason: 'data must be an object'),
        },
      ),
    );
  }
}
