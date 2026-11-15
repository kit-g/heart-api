part of 'inputs.dart';

class ApiTokenCreateIn {
  final String name;
  final ApiTokenExpiry expiry;
  final ApiTokenPurpose? purpose;

  /// What the token may read, `read` always among them: a personal token reads
  /// its owner's own training, and with `read:coaching` what their clients share
  /// with their assistant too. Never a write.
  final List<String> scopes;

  const new _({required this.name, required this.expiry, this.purpose, required this.scopes});

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
      scopes: switch (json['scopes']) {
        null => [Scope.read.value],
        final List<dynamic> asked when asked.every(meScopes.contains) => [
          ...{Scope.read.value, ...asked.cast<String>()},
        ]..sort(),
        _ => throw BadRequest(
          code: 'token_scope',
          reason: 'scopes is a list of what a personal token can hold: ${([...meScopes]..sort()).join(', ')}',
        ),
      },
    );
  }
}
