import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';

/// A wire shape: what the OpenAPI schema says a value is. A model's `toMap()`
/// writes it; `tool/openapi/shapes.dart` reads that `toMap()` and generates
/// the shape, and [encode] checks the one against the other while asserts are
/// on, which is every test run.
sealed class Shape<T> {
  const new();

  /// [value] as JSON, as far as it isn't already.
  Object? encode(T value) => value;

  /// The schema, registering named shapes in [components] as it goes.
  Map<String, Object?> describe(Components components);

  /// What is wrong with [json] as this shape, each at its JSON path; none
  /// when it conforms.
  Iterable<String> check(Object? json, String at);

  static const Shape<String> string = _Scalar('string');
  static const Shape<int> integer = _Scalar('integer');
  static const Shape<num> number = _Scalar('number');
  static const Shape<bool> boolean = _Scalar('boolean');

  /// A string the server already formatted as an ISO-8601 moment.
  static const Shape<String> isoString = _Scalar('string', format: 'date-time');

  /// A boolean the wire still writes as `0` or `1`.
  static const Shape<bool> flag = _Flag();

  /// One of [values], written as [wire] (an enum's `value` or `name`).
  static Shape<E> enumOf<E>(Iterable<E> values, String Function(E) wire) => _Enum(values, wire);

  static Shape<Iterable<V>> list<V>(Shape<V> items) => _List(items);

  /// Always present, possibly null.
  static Shape<V?> nullable<V>(Shape<V> shape) => _Nullable(shape);

  /// An object keyed by data rather than by name, such as records by kind.
  static Shape<Map<String, V>> mapOf<V>(Shape<V> values) => _MapOf(values);

  /// A named model, written by its own `toMap()`, which [fields]
  /// describe. [open] for a shape that carries keys a newer build wrote
  /// (`tolerant.dart`), which the check then lets through. [values] for the
  /// keys a `toMap()` computes, such as rules by the name they're used under.
  static Shape<T> model<T extends Model>(
    String name,
    Map<String, Field> fields, {
    String? description,
    bool open = false,
    Shape<Object?>? values,
  }) {
    return _Model(name, fields, description: description, open: open, values: values);
  }

  /// A named object a `toMap()` writes inline (a map literal, not a model of
  /// its own): described, and checked as part of the model that writes it,
  /// never encoded on its own. What the generator writes for `{'k': v}`.
  static Shape<Object?> described(
    String name,
    Map<String, Field> fields, {
    String? description,
    bool open = false,
    Shape<Object?>? values,
  }) {
    return _Described(name, fields, description: description, open: open, values: values);
  }

  /// `Paginated`'s body: [itemsKey] holding [items], the next page's
  /// `cursor` while there is one, and [extra] beside them.
  static Shape<Paginated<V>> page<V extends Model>(
    String itemsKey,
    Shape<V> items, {
    Map<String, Shape<Object?>> extra = const {},
  }) {
    return _Page(itemsKey, items, extra: extra);
  }

  /// A value nobody models here, such as published content passed through:
  /// the spec says [why] in words, and nothing is checked.
  static Shape<Object?> unknown(String why) => _Unknown(why);
}

/// One key of an object shape: present always ([Field.required]), or only when
/// its value is non-null ([Field.optional], the `'key': ?value` of a map
/// literal).
final class Field {
  final Shape<Object?> shape;
  final bool required;
  final String? description;

  const new required(this.shape, [this.description]) : required = true;

  const new optional(this.shape, [this.description]) : required = false;
}

/// The named schemas of one document: each shape once, by its name.
class Components {
  final Map<String, Map<String, Object?>> schemas = {};
  final Set<String> _building = {};

  Map<String, Object?> ref(String name, Map<String, Object?> Function() build) {
    if (!schemas.containsKey(name) && _building.add(name)) {
      schemas[name] = build();
      _building.remove(name);
    }
    return {r'$ref': '#/components/schemas/$name'};
  }
}

/// What `tool/openapi/shapes.dart` cannot read from a `toMap()`, or reads
/// short of what the spec should say, written by hand: the entries of
/// `shapeOverrides`, keyed `Object.key` (`Object.*` for its spread or computed
/// keys) as the generator names them.
final class ShapeOverride {
  final Shape<Object?>? shape;
  final String? description;

  /// Why the object carries keys nobody declares, for [ShapeOverride.open].
  final String? open;

  /// [shape] in place of the one inferred, or of a hole.
  const new shape(Shape<Object?> this.shape, {this.description}) : open = null;

  /// The inferred shape, with [description].
  const new describe(String this.description) : shape = null, open = null;

  /// An object whose spread or computed keys no declaration names: open, for
  /// the reason [open].
  const new open(String this.open) : shape = null, description = null;
}

/// Thrown by an encode, while asserts are on, when a `toMap()` writes what its
/// shape does not say.
class ShapeMismatch extends Error {
  final String shape;
  final List<String> problems;

  new(this.shape, this.problems);

  @override
  String toString() => 'ShapeMismatch($shape):\n  ${problems.join('\n  ')}';
}

class _Scalar<T> extends Shape<T> {
  final String type;
  final String? format;

  const new(this.type, {this.format});

  @override
  Map<String, Object?> describe(Components components) => {'type': type, 'format': ?format};

  @override
  Iterable<String> check(Object? json, String at) sync* {
    final ok = switch (type) {
      'string' => json is String,
      'integer' => json is int,
      'number' => json is num,
      'boolean' => json is bool,
      _ => false,
    };
    if (!ok) yield '$at: expected $type, got ${_kind(json)}';
  }
}

class _Flag extends Shape<bool> {
  const new();

  @override
  Map<String, Object?> describe(Components components) => {
    'type': 'integer',
    'enum': [0, 1],
  };

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (json != 0 && json != 1) yield '$at: expected 0 or 1, got ${_kind(json)}';
  }
}

class _Enum<E> extends Shape<E> {
  final Iterable<E> values;
  final String Function(E) wire;

  new(this.values, this.wire);

  @override
  Map<String, Object?> describe(Components components) => {'type': 'string', 'enum': values.map(wire).toList()};

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (!values.map(wire).contains(json)) yield '$at: expected one of ${values.map(wire).join(', ')}, got $json';
  }
}

class _List<V> extends Shape<Iterable<V>> {
  final Shape<V> items;

  new(this.items);

  @override
  Map<String, Object?> describe(Components components) => {'type': 'array', 'items': items.describe(components)};

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (json is! List) {
      yield '$at: expected an array, got ${_kind(json)}';
      return;
    }
    for (final (index, each) in json.indexed) {
      yield* items.check(each, '$at[$index]');
    }
  }
}

class _Nullable<V> extends Shape<V?> {
  final Shape<V> shape;

  new(this.shape);

  @override
  Map<String, Object?> describe(Components components) => {
    'oneOf': [
      shape.describe(components),
      {'type': 'null'},
    ],
  };

  @override
  Iterable<String> check(Object? json, String at) => json == null ? const [] : shape.check(json, at);
}

class _MapOf<V> extends Shape<Map<String, V>> {
  final Shape<V> values;

  new(this.values);

  @override
  Map<String, Object?> describe(Components components) => {
    'type': 'object',
    'additionalProperties': values.describe(components),
  };

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (json is! Map) {
      yield '$at: expected an object, got ${_kind(json)}';
      return;
    }
    for (final MapEntry(:key, :value) in json.entries) {
      yield* values.check(value, '$at.$key');
    }
  }
}

/// What object shapes share: named properties, each required or optional.
abstract class _Named<T> extends Shape<T> {
  final String name;
  final String? description;

  /// What the keys [properties] doesn't name hold, when they're data.
  final Shape<Object?>? values;

  const new(this.name, {this.description, this.values});

  Map<String, Field> get properties;

  bool get open => false;

  @override
  Map<String, Object?> describe(Components components) {
    return components.ref(name, () {
      final properties = this.properties;
      return {
        'type': 'object',
        'description': ?description,
        'properties': {
          for (final MapEntry(:key, value: field) in properties.entries)
            key: {...field.shape.describe(components), 'description': ?field.description},
        },
        'required': [
          for (final MapEntry(:key, value: field) in properties.entries)
            if (field.required) key,
        ],
        if (values case final values?)
          'additionalProperties': values.describe(components)
        else if (!open)
          'additionalProperties': false,
      };
    });
  }

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (json is! Map) {
      yield '$at: expected $name, got ${_kind(json)}';
      return;
    }
    final properties = this.properties;
    for (final MapEntry(:key, value: field) in properties.entries) {
      if (!json.containsKey(key)) {
        if (field.required) yield '$at.$key: required by $name, missing';
        continue;
      }
      final value = json[key];
      // an optional key is left out rather than written as null, unless its
      // shape says null is a value (`if (spoken) 'rest': rest`)
      if (value == null && !field.required && field.shape is! _Nullable) {
        yield '$at.$key: optional in $name, so left out when null, but written as null';
        continue;
      }
      yield* field.shape.check(value, '$at.$key');
    }
    if (open) return;
    for (final MapEntry(:key, :value) in json.entries) {
      if (properties.containsKey(key)) continue;
      if (values case final values?) {
        yield* values.check(value, '$at.$key');
      } else {
        yield '$at.$key: not in $name';
      }
    }
  }
}

class _Model<T extends Model> extends _Named<T> {
  final Map<String, Field> fields;
  @override
  final bool open;

  const new(super.name, this.fields, {super.description, this.open = false, super.values});

  @override
  Map<String, Field> get properties => fields;

  @override
  Object? encode(T value) {
    final map = value.toMap();
    assert(() {
      final problems = check(map, name).toList();
      if (problems.isNotEmpty) throw ShapeMismatch(name, problems);
      return true;
    }());
    return map;
  }
}

class _Described extends _Named<Object?> {
  final Map<String, Field> fields;
  @override
  final bool open;

  const new(super.name, this.fields, {super.description, this.open = false, super.values});

  @override
  Map<String, Field> get properties => fields;
}

class _Page<V extends Model> extends Shape<Paginated<V>> {
  final String itemsKey;
  final Shape<V> items;
  final Map<String, Shape<Object?>> extra;

  new(this.itemsKey, this.items, {this.extra = const {}});

  @override
  Object? encode(Paginated<V> value) {
    assert(value.itemsKey == itemsKey, 'a page of $itemsKey answered with ${value.itemsKey}');
    assert(
      value.extra.keys.every(extra.containsKey),
      'a page of $itemsKey carries undeclared ${value.extra.keys.where((key) => !extra.containsKey(key))}',
    );
    return {
      itemsKey: [for (final each in value) items.encode(each)],
      'cursor': ?value.cursor,
      // already written by whoever built the page, so only checked
      for (final MapEntry(:key, :value) in value.extra.entries) key: _checked(extra[key]!, value, key),
    };
  }

  static Object? _checked(Shape<Object?> shape, Object? json, String key) {
    assert(() {
      final problems = shape.check(json, key).toList();
      if (problems.isNotEmpty) throw ShapeMismatch(key, problems);
      return true;
    }());
    return json;
  }

  @override
  Map<String, Object?> describe(Components components) => {
    'type': 'object',
    'properties': {
      itemsKey: {'type': 'array', 'items': items.describe(components)},
      'cursor': {'type': 'string', 'description': 'The next page, while there is one: pass it back as `cursor`.'},
      for (final MapEntry(:key, :value) in extra.entries) key: value.describe(components),
    },
    'required': [itemsKey],
    'additionalProperties': false,
  };

  @override
  Iterable<String> check(Object? json, String at) sync* {
    if (json is! Map) {
      yield '$at: expected a page, got ${_kind(json)}';
      return;
    }
    yield* _List(items).check(json[itemsKey], '$at.$itemsKey');
    if (json.containsKey('cursor')) yield* Shape.string.check(json['cursor'], '$at.cursor');
    for (final MapEntry(:key, :value) in json.entries) {
      if (key == itemsKey || key == 'cursor') continue;
      if (extra[key] case final shape?) {
        yield* shape.check(value, '$at.$key');
      } else {
        yield '$at.$key: not in a page of $itemsKey';
      }
    }
  }
}

class _Unknown extends Shape<Object?> {
  final String why;

  const new(this.why);

  @override
  Object? encode(Object? value) => switch (value) {
    final Model model => model.toMap(),
    _ => value,
  };

  @override
  Map<String, Object?> describe(Components components) => {'description': why};

  @override
  Iterable<String> check(Object? json, String at) => const [];
}

String _kind(Object? json) => switch (json) {
  null => 'null',
  String() => 'a string',
  int() => 'an integer',
  num() => 'a number',
  bool() => 'a boolean',
  List() => 'an array',
  Map() => 'an object',
  _ => json.runtimeType.toString(),
};
