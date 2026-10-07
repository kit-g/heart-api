import 'misc.dart';

/// An app the account let read its data through OAuth: an AI assistant such
/// as Claude or ChatGPT, or any other client it approved on the consent
/// screen. Disconnecting it revokes every token it holds.
abstract interface class ConnectedApp implements Model {
  String get id;

  /// The client's own identifier: for most, the URL of its metadata document.
  String get clientId;

  /// The name the client gave itself when the account approved it.
  String get name;

  List<String> get scopes;

  /// What its tokens can reach (the MCP server or the `/me` API).
  String get resource;

  DateTime get connectedAt;

  DateTime? get lastUsedAt;

  factory({
    required String id,
    required String clientId,
    required String name,
    required List<String> scopes,
    required String resource,
    required DateTime connectedAt,
    DateTime? lastUsedAt,
  }) = _ConnectedApp;

  /// Wire/JSON shape — camelCase.
  factory fromJson(Map json) {
    return _ConnectedApp(
      id: json['id'].toString(),
      clientId: json['clientId'] as String,
      name: json['name'] as String,
      scopes: [...(json['scopes'] as List).cast<String>()],
      resource: json['resource'] as String,
      connectedAt: DateTime.parse(json['connectedAt'] as String),
      lastUsedAt: switch (json['lastUsedAt']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
    );
  }

  /// Database row shape — an `oauth_grants` row, snake_case.
  factory fromRow(Map<String, dynamic> row) {
    return _ConnectedApp(
      id: row['id'].toString(),
      clientId: row['client_id'] as String,
      name: row['client_name'] as String,
      scopes: [...(row['scopes'] as List).cast<String>()],
      resource: row['resource'] as String,
      connectedAt: row['created_at'] as DateTime,
      lastUsedAt: row['last_used_at'] as DateTime?,
    );
  }
}

class _ConnectedApp implements ConnectedApp {
  @override
  final String id;
  @override
  final String clientId;
  @override
  final String name;
  @override
  final List<String> scopes;
  @override
  final String resource;
  @override
  final DateTime connectedAt;
  @override
  final DateTime? lastUsedAt;

  const new({
    required this.id,
    required this.clientId,
    required this.name,
    required this.scopes,
    required this.resource,
    required this.connectedAt,
    this.lastUsedAt,
  });

  @override
  bool operator ==(Object other) => other is ConnectedApp && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientId': clientId,
      'name': name,
      'scopes': scopes,
      'resource': resource,
      'connectedAt': connectedAt.toUtc().toIso8601String(),
      'lastUsedAt': ?lastUsedAt?.toUtc().toIso8601String(),
    };
  }
}
