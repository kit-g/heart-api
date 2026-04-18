abstract mixin class DynamoItem {
  Map<String, dynamic> toDynamoItem();
}

extension on String {
  /// converts a camelCase string to snake_case
  String toSnake() {
    return replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) => '${match[1]}_${match[2]}').toLowerCase();
  }
}

extension CaseMap on Map<String, dynamic> {
  /// converts every key in this to snake_case,
  /// expecting it to be in camelCase initially
  Map<String, dynamic> toSnake() {
    return {
      for (final MapEntry(:key, :value) in entries) key.toSnake(): value,
    };
  }
}
