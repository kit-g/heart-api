import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/core/openapi/query.dart';
import 'package:heart/core/openapi/shape.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

class _Thing implements Model {
  final Map<String, dynamic> map;

  const new(this.map);

  @override
  Map<String, dynamic> toMap() => map;
}

final Shape<_Thing> _thing = .model('Thing', {
  'id': const .required(.string),
  'note': const .optional(.string, 'A line about it.'),
  'rest': .optional(.nullable(.integer)),
  'kind': .required(.enumOf<String>(const ['a', 'b'], (kind) => kind)),
});

const _valid = {'id': 'x', 'kind': 'a'};

class _Search {
  final String q;
  final int limit;
  final bool archived;
  final String? cursor;

  const new(this.q, this.limit, {required this.archived, this.cursor});

  static _Search read(Query q) {
    return _Search(
      q.string('q', maxLength: 10),
      q.integer('limit', defaultValue: 30, min: 1, max: 100),
      archived: q.boolean('archived'),
      cursor: q.stringOrNull('cursor', description: 'The next page.'),
    );
  }
}

void main() {
  group('a shape checks what a toMap() wrote', () {
    test('and passes what it declares', () {
      expect(_thing.check(_valid, 'body'), isEmpty);
      expect(_thing.check({..._valid, 'note': 'n', 'rest': 60}, 'body'), isEmpty);
    });

    test('and fails a key it does not name, one it requires, and a wrong type', () {
      expect(_thing.check({..._valid, 'heartRate': 120}, 'body'), ['body.heartRate: not in Thing']);
      expect(_thing.check({'kind': 'a'}, 'body'), ['body.id: required by Thing, missing']);
      expect(_thing.check({..._valid, 'id': 1}, 'body'), ['body.id: expected string, got an integer']);
      expect(_thing.check({..._valid, 'kind': 'c'}, 'body'), ['body.kind: expected one of a, b, got c']);
    });

    test('and writes an optional key as null only where its shape says null is a value', () {
      expect(_thing.check({..._valid, 'rest': null}, 'body'), isEmpty);
      expect(_thing.check({..._valid, 'note': null}, 'body'), [
        'body.note: optional in Thing, so left out when null, but written as null',
      ]);
    });

    test('and lets an open shape carry keys nobody declares', () {
      final Shape<_Thing> open = .model('Open', {'id': const .required(.string)}, open: true);
      expect(open.check({'id': 'x', 'newer': 1}, 'body'), isEmpty);
    });

    test('and holds keys it can\'t name to [values]', () {
      final Shape<Object?> byName = .described('ByName', {'id': const .required(.string)}, values: Shape.integer);
      expect(byName.check({'id': 'x', 'squat': 1, 'bench': 2}, 'body'), isEmpty);
      expect(byName.check({'id': 'x', 'squat': 'heavy'}, 'body'), ['body.squat: expected integer, got a string']);
      final components = Components();
      byName.describe(components);
      expect(components.schemas['ByName']!['additionalProperties'], {'type': 'integer'});
    });

    test('and encoding fails on a mismatch while asserts are on', () {
      expect(() => _thing.encode(const _Thing({'kind': 'a'})), throwsA(isA<ShapeMismatch>()));
      expect(_thing.encode(const _Thing(_valid)), _valid);
    });
  });

  test('a shape describes itself once, by its name', () {
    final components = Components();
    expect(Shape.list(_thing).describe(components), {
      'type': 'array',
      'items': {r'$ref': '#/components/schemas/Thing'},
    });
    _thing.describe(components);
    final schema = components.schemas['Thing']!;
    expect(components.schemas.keys, ['Thing']);
    expect(schema['required'], ['id', 'kind']);
    expect(schema['additionalProperties'], false);
    expect((schema['properties']! as Map)['note'], {'type': 'string', 'description': 'A line about it.'});
  });

  group('a query reader', () {
    test('parses a request', () {
      final read = _Search.read(.values({'q': 'bench', 'limit': '500', 'archived': 'true'}));
      expect([read.q, read.limit, read.archived, read.cursor], ['bench', 100, true, null]);
    });

    test('refuses what it requires and can\'t parse', () {
      expect(() => _Search.read(.values(const {})), throwsA(isA<BadRequest>()));
      expect(() => _Search.read(.values({'q': 'x', 'limit': 'many'})), throwsA(isA<BadRequest>()));
      expect(() => _Search.read(.values({'q': 'x', 'archived': 'maybe'})), throwsA(isA<BadRequest>()));
    });

    test('lists what it reads when recording, from the same code', () {
      final recording = Query.recording();
      _Search.read(recording);
      expect(recording.parameters.map((parameter) => parameter.name), ['q', 'limit', 'archived', 'cursor']);
      expect(recording.parameters.first.toMap(), {
        'name': 'q',
        'in': 'query',
        'required': true,
        'schema': {'type': 'string', 'minLength': 1, 'maxLength': 10},
      });
      expect(recording.parameters[1].schema, {'type': 'integer', 'minimum': 1, 'maximum': 100, 'default': 30});
    });

    test('reads a path parameter, and an optional choice', () {
      final query = Query.values({'status': 'b'}, path: {'id': 'x'});
      expect(query.path('id'), 'x');
      expect(query.choiceOrNull('status', const ['a', 'b'], (it) => it), 'b');
      expect(query.choiceOrNull('other', const ['a', 'b'], (it) => it), isNull);
      expect(
        () => Query.values({'status': 'c'}).choiceOrNull('status', const ['a'], (it) => it),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('an endpoint', () {
    final found = Endpoint.of<String, _Thing>(
      (_, id) async => _Thing({'id': id, 'kind': 'a'}),
      input: (query) => query.path('id', format: 'uuid'),
      reply: .json(_thing),
      summary: 'One thing',
      errors: [const .notFound('thing_not_found')],
    );

    test('reads its input, runs the handler and writes the reply', () async {
      final body = await found.call(bareRequest(method: Method.get), path: {'id': 'x'});
      expect(body!.toMap(), {'id': 'x', 'kind': 'a'});
    });

    test('fails on a refusal it does not declare while asserts are on', () {
      final endpoint = Endpoint.none<_Thing>((_) => throw const Forbidden(reason: 'no'), reply: .json(_thing));
      expect(() => endpoint.call(bareRequest()), throwsA(isA<AssertionError>()));
    });

    test('lets a declared refusal through as thrown', () {
      final endpoint = Endpoint.none<_Thing>(
        (_) => throw const NotFound(type: 'thing', id: 'x'),
        reply: .json(_thing),
        errors: [const .notFound()],
      );
      expect(() => endpoint.call(bareRequest()), throwsA(isA<NotFound>()));
    });

    test('answers a page, with its cursor and what it declares beside it', () async {
      final endpoint = Endpoint.none<Paginated<_Thing>>(
        (_) async => const Paginated(
          items: [_Thing(_valid)],
          itemsKey: 'things',
          cursor: 'next',
          extra: {'total': 1},
        ),
        reply: .json(.page('things', _thing, extra: {'total': Shape.integer})),
      );
      expect((await endpoint.call(bareRequest()))!.toMap(), {
        'things': [_valid],
        'cursor': 'next',
        'total': 1,
      });
    });
  });

  test('the document says what the table declares', () {
    final document = openApiDocument(
      {
        ('/things/:id', Method.get): Endpoint.of<String, _Thing>(
          (_, id) async => _Thing({'id': id, 'kind': 'a'}),
          input: (query) => query.path('id'),
          reply: .json(_thing),
          summary: 'One thing',
          errors: [const .notFound('thing_not_found')],
        ),
      },
      prefix: '/v',
      title: 'Things',
      version: '1',
      servers: const ['https://example.test'],
      securitySchemes: {
        'token': {'type': 'http', 'scheme': 'bearer'},
      },
      everywhere: [const .unauthorized()],
    );

    expect(document['openapi'], '3.1.0');
    expect(document['servers'], [
      {'url': 'https://example.test'},
    ]);
    expect(document['security'], [
      {'token': const <String>[]},
    ]);
    final operation = ((document['paths']! as Map)['/v/things/{id}'] as Map)['get'] as Map;
    expect(operation['operationId'], 'getVThingsId');
    expect(operation['summary'], 'One thing');
    expect((operation['parameters'] as List).single, containsPair('in', 'path'));
    expect((operation['responses'] as Map).keys, containsAll(['200', '400', '404', '401']));
    expect(((document['components']! as Map)['schemas'] as Map).keys, containsAll(['Thing', 'Error']));
  });
}
