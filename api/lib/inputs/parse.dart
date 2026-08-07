part of 'inputs.dart';

/// Pattern-match-style parse helpers. Each method matches the happy path; any
/// other shape throws [BadRequest] so the route layer turns it into a 400.

extension on Map<String, dynamic> {
  /// Required non-empty string. Optional [maxLength] caps the size.
  String string(String field, {int? maxLength}) {
    return switch (this[field]) {
      String s when s.isNotEmpty && (maxLength == null || s.length <= maxLength) => s,
      _ => throw BadRequest(reason: _stringMsg(field, maxLength: maxLength)),
    };
  }

  /// Optional string. Absent stays null; present must be non-empty and
  /// within [maxLength].
  String? stringOrNull(String field, {int? maxLength}) {
    return switch (this[field]) {
      null => null,
      String s when s.isNotEmpty && (maxLength == null || s.length <= maxLength) => s,
      _ => throw BadRequest(reason: _stringMsg(field, maxLength: maxLength)),
    };
  }

  /// Optional bool. Absent stays null.
  bool? booleanOrNull(String field) {
    return switch (this[field]) {
      null => null,
      bool b => b,
      _ => throw BadRequest(reason: '$field must be a boolean'),
    };
  }

  /// Parses the value as a string then runs [parser]; any throw from [parser]
  /// becomes a 400 with a helpful message.
  T parsed<T>(String field, T Function(String) parser) {
    final raw = string(field);
    try {
      return parser(raw);
    } catch (_) {
      throw BadRequest(reason: '$field has an invalid value: $raw');
    }
  }

  /// Object/Map field. Returns [orElse] when absent.
  Map<String, dynamic> mapping(String field, {Map<String, dynamic> orElse = const {}}) {
    return switch (this[field]) {
      null => orElse,
      Map m => m.cast<String, dynamic>(),
      _ => throw BadRequest(reason: '$field must be an object'),
    };
  }

  /// Required number, optionally bounded below by [min] (exclusive).
  num number(String field, {num? exclusiveMin}) {
    return switch (this[field]) {
      num n when exclusiveMin == null || n > exclusiveMin => n,
      _ => throw BadRequest(reason: _numberMsg(field, exclusiveMin: exclusiveMin)),
    };
  }

  /// Optional bool. Returns [orElse] when absent.
  bool boolean(String field, {bool orElse = false}) {
    return switch (this[field]) {
      null => orElse,
      bool b => b,
      _ => throw BadRequest(reason: '$field must be a boolean'),
    };
  }

  /// Required ISO-8601 date or timestamp.
  DateTime timestamp(String field) {
    return switch (dateOrNull(field)) {
      DateTime d => d,
      null => throw BadRequest(reason: '$field is required'),
    };
  }

  /// Optional ISO-8601 date (`2026-12-25`) or timestamp. Absent stays absent.
  DateTime? dateOrNull(String field) {
    return switch (this[field]) {
      null => null,
      String s => DateTime.tryParse(s) ?? (throw BadRequest(reason: '$field must be an ISO-8601 date')),
      _ => throw BadRequest(reason: '$field must be an ISO-8601 date'),
    };
  }

  /// Required non-empty list of objects.
  List<Map<String, dynamic>> objects(String field) {
    return switch (this[field]) {
      List l when l.isNotEmpty && l.every((each) => each is Map) => [
        for (final each in l) (each as Map).cast<String, dynamic>(),
      ],
      _ => throw BadRequest(reason: '$field must be a non-empty array of objects'),
    };
  }
}

extension on Map<String, String> {
  /// Required non-empty query param.
  String string(String field) {
    return switch (this[field]) {
      String s when s.isNotEmpty => s,
      _ => throw BadRequest(reason: '$field is required'),
    };
  }

  /// Optional query param. Empty string is treated as absent.
  String? stringOrNull(String field) {
    return switch (this[field]) {
      null => null,
      String s when s.isNotEmpty => s,
      _ => null,
    };
  }

  /// Parses a query param via [parser]; throws 400 on failure.
  T parsed<T>(String field, T Function(String) parser) {
    final raw = string(field);
    try {
      return parser(raw);
    } catch (_) {
      throw BadRequest(reason: '$field has an invalid value: $raw');
    }
  }

  /// Required integer with optional [min]/[max] clamping. Supply [defaultValue]
  /// to make the param optional.
  int integer(String field, {int? min, int? max, int? defaultValue}) {
    final raw = this[field];
    if (raw == null || raw.isEmpty) {
      if (defaultValue != null) return defaultValue.clamped(min, max);
      throw BadRequest(reason: '$field is required');
    }
    return switch (int.tryParse(raw)) {
      int n => n.clamped(min, max),
      null => throw BadRequest(reason: '$field must be an integer'),
    };
  }
}

String _stringMsg(String field, {int? maxLength}) {
  return maxLength == null
      ? '$field must be a non-empty string'
      : '$field must be a non-empty string (max $maxLength chars)';
}

String _numberMsg(String field, {num? exclusiveMin}) {
  return exclusiveMin == null ? '$field must be a number' : '$field must be a number greater than $exclusiveMin';
}

extension on int {
  int clamped([int? min, int? max]) {
    if (min != null && this < min) return min;
    if (max != null && this > max) return max;
    return this;
  }
}
