import 'misc.dart';

/// A flat, per-user bucket for [Template]s.
///
/// A coach with a roster files their masters by student or by training block; an
/// individual files theirs by split. Both are the same object — a name and a
/// position — so a folder carries no coaching semantics of its own and is never
/// shared as an object. Sharing a folder is shorthand for sharing every template
/// in it, and the recipient's copies arrive unfiled.
///
/// Folders do not nest. A template belongs to at most one, and belongs to none
/// when [Template.folderId] is null.
abstract interface class TemplateFolder implements Model, Comparable<TemplateFolder> {
  /// Null only before the server has minted one.
  String? get id;

  String get name;

  /// Owner-arranged position in the folder list. Ties break on [name].
  int get order;

  /// How many of the owner's templates are filed here. Read-only — the server
  /// counts it on read; nothing writes it.
  int get templateCount;

  DateTime? get createdAt;

  factory TemplateFolder({
    String? id,
    required String name,
    int order,
    int templateCount,
    DateTime? createdAt,
  }) = _TemplateFolder;

  /// Wire/JSON shape — camelCase, as sent to and received from the app.
  factory TemplateFolder.fromJson(Map json) {
    return _TemplateFolder(
      id: json['id']?.toString(),
      name: switch (json['name']) {
        final String n when n.trim().isNotEmpty => n,
        final other => throw ArgumentError.value(other, 'name', 'a folder needs a name'),
      },
      order: switch (json['order']) {
        final num o => o.toInt(),
        _ => 0,
      },
      templateCount: switch (json['templateCount']) {
        final num c => c.toInt(),
        _ => 0,
      },
      createdAt: switch (json['createdAt']) {
        final DateTime d => d,
        final String s => DateTime.parse(s),
        _ => null,
      },
    );
  }

  /// Database row shape — snake_case column names. `template_count` is present
  /// only on the list query; it reads as 0 elsewhere.
  factory TemplateFolder.fromRow(Map<String, dynamic> row) {
    return _TemplateFolder(
      id: row['id'].toString(),
      name: row['name'] as String,
      order: (row['order_index'] as num?)?.toInt() ?? 0,
      templateCount: (row['template_count'] as num?)?.toInt() ?? 0,
      createdAt: switch (row['created_at']) {
        final DateTime d => d,
        final String s => DateTime.parse(s),
        _ => null,
      },
    );
  }

  TemplateFolder copyWith({String? id, String? name, int? order, int? templateCount});
}

class _TemplateFolder implements TemplateFolder {
  @override
  final String? id;
  @override
  final String name;
  @override
  final int order;
  @override
  final int templateCount;
  @override
  final DateTime? createdAt;

  const _TemplateFolder({
    this.id,
    required this.name,
    this.order = 0,
    this.templateCount = 0,
    this.createdAt,
  });

  @override
  TemplateFolder copyWith({String? id, String? name, int? order, int? templateCount}) {
    return _TemplateFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      templateCount: templateCount ?? this.templateCount,
      createdAt: createdAt,
    );
  }

  @override
  int compareTo(TemplateFolder other) {
    final byOrder = order.compareTo(other.order);
    return byOrder != 0 ? byOrder : name.toLowerCase().compareTo(other.name.toLowerCase());
  }

  @override
  bool operator ==(Object other) => other is TemplateFolder && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'name': name,
      'order': order,
      'templateCount': templateCount,
      'createdAt': ?createdAt?.toUtc().toIso8601String(),
    };
  }
}
