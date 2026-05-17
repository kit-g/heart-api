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

extension on int {
  int clamped([int? min, int? max]) {
    if (min != null && this < min) return min;
    if (max != null && this > max) return max;
    return this;
  }
}
