import 'package:heart/models/errors.dart';
import 'package:relic/relic.dart';

/// A request's path and query parameters, read the way `parse.dart` reads
/// them: happy path returns, anything else is a [BadRequest].
///
/// The same reader also describes them. [Query.recording] answers every read
/// with a stand-in value and notes what was asked for, so running an input's
/// `read` once yields its OpenAPI parameters: the parsing *is* the
/// declaration. A read that branches on a value only sees the stand-ins, so
/// the checks between parameters (`from` before `to`) stay out of the spec,
/// as prose does.
class Query {
  final Map<String, String> _query;
  final String? Function(String name) _path;
  final List<Parameter>? _recorded;

  new _(this._query, this._path, this._recorded);

  /// [request]'s routing context is read only when a path parameter is.
  factory of(Request request) {
    return ._(request.url.queryParameters, (name) => request.rawPathParameters[Symbol(name)], null);
  }

  /// For a test, which cannot set relic's routing context.
  factory values(Map<String, String> query, {Map<String, String> path = const {}}) => ._(query, path.lookup, null);

  factory recording() => ._(const {}, (_) => null, []);

  /// What a recording run asked for, in the order it asked.
  List<Parameter> get parameters => List.unmodifiable(_recorded ?? const []);

  bool get _isRecording => _recorded != null;

  T _note<T>(Parameter parameter, T standIn) {
    _recorded!.add(parameter);
    return standIn;
  }

  /// A `:name` path segment, raw: what an id that isn't one means (a 404, as
  /// a rule) is the route's to say.
  String path(String name, {String? description, String? format}) {
    if (_isRecording) {
      return _note(
        .new(
          name,
          location: 'path',
          required: true,
          schema: {'type': 'string', 'format': ?format},
          description: description,
        ),
        _standInId,
      );
    }
    return _path(name)!;
  }

  /// Required non-empty query param.
  String string(String field, {String? description}) {
    if (_isRecording) {
      return _note(
        .new(field, required: true, schema: {'type': 'string', 'minLength': 1}, description: description),
        'x',
      );
    }
    return switch (_query[field]) {
      String s when s.isNotEmpty => s,
      _ => throw BadRequest(reason: '$field is required'),
    };
  }

  /// Optional query param. Empty string is treated as absent. [format] and
  /// [maxLength] only describe it; checking them stays the caller's.
  String? stringOrNull(String field, {String? description, String? format, int? maxLength}) {
    if (_isRecording) {
      return _note(
        .new(
          field,
          schema: {'type': 'string', 'format': ?format, 'maxLength': ?maxLength},
          description: description,
        ),
        null,
      );
    }
    return switch (_query[field]) {
      null => null,
      String s when s.isNotEmpty => s,
      _ => null,
    };
  }

  /// A required one of [values], by its [wire] name.
  E choice<E>(String field, Iterable<E> values, String Function(E) wire, {String? description}) {
    if (_isRecording) {
      return _note(
        .new(
          field,
          required: true,
          schema: {'type': 'string', 'enum': values.map(wire).toList()},
          description: description,
        ),
        values.first,
      );
    }
    final raw = string(field);
    for (final value in values) {
      if (wire(value) == raw) return value;
    }
    throw BadRequest(reason: '$field has an invalid value: $raw');
  }

  /// Optional boolean query param; absent or empty means [orElse].
  bool boolean(String field, {bool orElse = false, String? description}) {
    if (_isRecording) {
      return _note(.new(field, schema: {'type': 'boolean', 'default': orElse}, description: description), orElse);
    }
    return switch (stringOrNull(field)) {
      null => orElse,
      'true' => true,
      'false' => false,
      final s => throw BadRequest(reason: '$field must be true or false, got: $s'),
    };
  }

  /// Required integer with optional [min]/[max] clamping. Supply
  /// [defaultValue] to make the param optional. Out of range is clamped, not
  /// refused, which the schema can only say in words.
  int integer(String field, {int? min, int? max, int? defaultValue, String? description}) {
    if (_isRecording) {
      return _note(
        .new(
          field,
          required: defaultValue == null,
          schema: {'type': 'integer', 'minimum': ?min, 'maximum': ?max, 'default': ?defaultValue},
          description: [?description, if (min != null || max != null) 'Out of range is clamped.'].join(' '),
        ),
        defaultValue ?? min ?? 0,
      );
    }
    final raw = _query[field];
    if (raw == null || raw.isEmpty) {
      if (defaultValue != null) return defaultValue._clamped(min, max);
      throw BadRequest(reason: '$field is required');
    }
    return switch (int.tryParse(raw)) {
      int n => n._clamped(min, max),
      null => throw BadRequest(reason: '$field must be an integer'),
    };
  }
}

/// One path or query parameter, as OpenAPI lists it.
class Parameter {
  final String name;
  final String location;
  final bool required;
  final Map<String, Object?> schema;
  final String? description;

  const new(this.name, {this.location = 'query', this.required = false, required this.schema, this.description});

  Map<String, Object?> toMap() => {
    'name': name,
    'in': location,
    'required': required,
    'schema': schema,
    if (description case final text? when text.isNotEmpty) 'description': text,
  };
}

/// A uuidv7, so an id check on a recording run passes.
const _standInId = '01900000-0000-7000-8000-000000000000';

extension on Map<String, String> {
  String? lookup(String key) => this[key];
}

extension on int {
  int _clamped([int? min, int? max]) {
    if (min != null && this < min) return min;
    if (max != null && this > max) return max;
    return this;
  }
}
