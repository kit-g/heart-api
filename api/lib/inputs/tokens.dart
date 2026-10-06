part of 'inputs.dart';

class ApiTokenCreateIn {
  final String name;
  final ApiTokenExpiry expiry;
  final ApiTokenPurpose? purpose;

  const new _({required this.name, required this.expiry, this.purpose});

  static Future<ApiTokenCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    final name = json.string('name', maxLength: ApiToken.maxNameLength).trim();
    if (name.isEmpty) throw const BadRequest(reason: 'name must not be blank');
    return ApiTokenCreateIn._(
      name: name,
      expiry: json.parsed('expiry', ApiTokenExpiry.fromString),
      purpose: switch (json['purpose']) {
        null => null,
        _ => json.parsed('purpose', ApiTokenPurpose.fromString),
      },
    );
  }
}

/// `GET /me/export?format=` — required, so a new default can never silently
/// change what an existing script downloads.
class ExportQuery {
  final ExportFormat format;

  const new _({required this.format});

  static ExportQuery fromRequest(Request req) {
    final q = req.url.queryParameters;
    return ExportQuery._(format: q.parsed('format', ExportFormat.fromString));
  }
}
