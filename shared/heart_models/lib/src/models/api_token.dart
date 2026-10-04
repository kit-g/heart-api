import 'misc.dart';

/// What a personal access token is for, as its owner said when minting it.
///
/// Optional and never checked against how the token is used: it exists so the
/// owner can tell their tokens apart and so the server can learn what people
/// build on the API. Wire values are the camelCase enum names.
enum ApiTokenPurpose {
  script,
  spreadsheet,
  homeAutomation,
  aiAssistant,
  other;

  factory fromString(String? v) {
    return values.firstWhere(
      (p) => p.name == v,
      orElse: () => throw ArgumentError.value(v, 'purpose', 'unknown token purpose'),
    );
  }
}

/// How long a newly minted token lives. A choice rather than a timestamp, so
/// the options can grow without clients computing dates.
enum ApiTokenExpiry {
  year,
  never;

  factory fromString(String? v) {
    return switch (v) {
      'year' => year,
      'never' => never,
      _ => throw ArgumentError.value(v, 'expiry', 'expiry is "year" or "never"'),
    };
  }
}

/// A personal access token as its owner sees it in a list: everything but the
/// secret, which exists in plaintext only once, in a [MintedApiToken].
///
/// A token is the user acting as themselves on the read-only `/me` surface,
/// from a script, a spreadsheet or an AI assistant.
abstract interface class ApiToken implements Model {
  /// Active tokens one account may hold at once. Revoked and expired ones
  /// don't count.
  static const maxActive = 5;

  static const maxNameLength = 100;

  String get id;

  String get name;

  ApiTokenPurpose? get purpose;

  /// The secret's last four characters, so the owner can match a token to
  /// the one pasted somewhere.
  String get hint;

  List<String> get scopes;

  DateTime get createdAt;

  DateTime? get lastUsedAt;

  /// Null when the token lives until revoked.
  DateTime? get expiresAt;

  DateTime? get revokedAt;

  /// Neither revoked nor past its expiry at [now].
  bool isActive([DateTime? now]);

  factory({
    required String id,
    required String name,
    ApiTokenPurpose? purpose,
    required String hint,
    List<String> scopes,
    required DateTime createdAt,
    DateTime? lastUsedAt,
    DateTime? expiresAt,
    DateTime? revokedAt,
  }) = _ApiToken;

  /// Wire/JSON shape — camelCase, as sent to the app.
  factory fromJson(Map json) {
    return _ApiToken(
      id: json['id'].toString(),
      name: json['name'] as String,
      purpose: switch (json['purpose']) {
        final String p => ApiTokenPurpose.fromString(p),
        _ => null,
      },
      hint: json['hint'] as String,
      scopes: [...?(json['scopes'] as List?)?.cast<String>()],
      createdAt: _date(json['createdAt'])!,
      lastUsedAt: _date(json['lastUsedAt']),
      expiresAt: _date(json['expiresAt']),
      revokedAt: _date(json['revokedAt']),
    );
  }

  /// Database row shape — snake_case column names.
  factory fromRow(Map<String, dynamic> row) {
    return _ApiToken(
      id: row['id'].toString(),
      name: row['name'] as String,
      purpose: switch (row['purpose']) {
        final String p => ApiTokenPurpose.fromString(p),
        _ => null,
      },
      hint: row['hint'] as String,
      scopes: [...?(row['scopes'] as List?)?.cast<String>()],
      createdAt: _date(row['created_at'])!,
      lastUsedAt: _date(row['last_used_at']),
      expiresAt: _date(row['expires_at']),
      revokedAt: _date(row['revoked_at']),
    );
  }
}

/// A token the moment it is created: the listed fields plus [secret], the
/// plaintext bearer value. The server keeps only a digest, so this is the one
/// time anyone sees it.
abstract interface class MintedApiToken implements Model {
  ApiToken get token;

  String get secret;

  factory({required ApiToken token, required String secret}) = _MintedApiToken;

  factory fromJson(Map json) {
    return _MintedApiToken(
      token: ApiToken.fromJson(json),
      secret: json['secret'] as String,
    );
  }
}

DateTime? _date(Object? v) {
  return switch (v) {
    final DateTime d => d,
    final String s => DateTime.parse(s),
    _ => null,
  };
}

class _ApiToken implements ApiToken {
  @override
  final String id;
  @override
  final String name;
  @override
  final ApiTokenPurpose? purpose;
  @override
  final String hint;
  @override
  final List<String> scopes;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastUsedAt;
  @override
  final DateTime? expiresAt;
  @override
  final DateTime? revokedAt;

  const new({
    required this.id,
    required this.name,
    this.purpose,
    required this.hint,
    this.scopes = const ['read'],
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.revokedAt,
  });

  @override
  bool isActive([DateTime? now]) {
    final at = now ?? DateTime.now();
    return revokedAt == null && (expiresAt == null || expiresAt!.isAfter(at));
  }

  @override
  bool operator ==(Object other) => other is ApiToken && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'purpose': ?purpose?.name,
      'hint': hint,
      'scopes': scopes,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastUsedAt': ?lastUsedAt?.toUtc().toIso8601String(),
      'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
      'revokedAt': ?revokedAt?.toUtc().toIso8601String(),
    };
  }
}

class _MintedApiToken implements MintedApiToken {
  @override
  final ApiToken token;
  @override
  final String secret;

  const new({required this.token, required this.secret});

  @override
  Map<String, dynamic> toMap() => {...token.toMap(), 'secret': secret};
}
