import 'package:heart/core/handler.dart';
import 'package:heart/core/openapi/query.dart';
import 'package:heart/core/openapi/shape.dart';
import 'package:heart/core/response.dart';
import 'package:heart/core/routing.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// Path and verb to endpoint: a [RouteTable] whose routes say what they read
/// and what they answer, so the table is also the OpenAPI document.
typedef EndpointTable = Map<(String, Method), Endpoint>;

/// What a route reads: its path and query parameters, parsed and checked.
typedef Input<Q> = Q Function(Query query);

/// A route as the router runs it and as the spec describes it, from the same
/// declaration: [Endpoint.of] binds a typed [Input] to a handler and encodes
/// its result through a [Reply], so a parameter the spec lists is one the
/// handler reads and a response the spec shows is the one it writes.
abstract interface class Endpoint {
  /// The route for the router: input parsed, handler run, result encoded.
  ModelHandler get handler;

  /// [handler] with [path] as the path parameters, for a test, which cannot
  /// set relic's routing context.
  Future<Model?> call(Request request, {Map<String, String>? path});

  /// This route's OpenAPI operation object.
  Map<String, Object?> operation(Components components, {required String id});

  /// A route that reads [input] and answers [reply]. [errors] are the
  /// refusals the handler itself can throw; a 400 for malformed input comes
  /// with any input, and the surface's own (401, 429) are the document's.
  static Endpoint of<Q, R>(
    Future<R> Function(Request request, Q input) handle, {
    required Input<Q> input,
    required Reply<R> reply,
    String? summary,
    List<Failure> errors = const [],
  }) {
    return _Endpoint(handle, input: input, reply: reply, summary: summary, errors: errors);
  }

  /// A route with nothing to read.
  static Endpoint none<R>(
    Future<R> Function(Request request) handle, {
    required Reply<R> reply,
    String? summary,
    List<Failure> errors = const [],
  }) {
    return _Endpoint<Null, R>(
      (request, _) => handle(request),
      input: null,
      reply: reply,
      summary: summary,
      errors: errors,
    );
  }

  /// A route not migrated yet: served as before, listed in the spec as
  /// undeclared.
  static Endpoint undeclared(ModelHandler handler, {String? summary}) => _Undeclared(handler, summary: summary);
}

/// How a handler's result goes on the wire, and what the spec says about it.
sealed class Reply<R> {
  const new();

  /// [shape] as JSON, with [status].
  static Reply<R> json<R>(Shape<R> shape, {int status = 200, String description = 'OK'}) {
    return _Json(shape, status: status, description: description);
  }

  /// A file of [mimeType] as the body ([Download]), or a `303` to one too
  /// large to answer inline ([SeeOther]).
  static Reply<Model> download({required String mimeType, String description = 'The file'}) {
    return _Download(mimeType, description: description);
  }

  Model wrap(R result);

  Map<String, Object?> describe(Components components);
}

/// One refusal a route can answer with: its status and stable `code`.
class Failure {
  final int status;
  final String code;
  final String? description;

  const new(this.status, this.code, {this.description});

  const new badRequest([this.code = 'bad_request', this.description]) : status = 400;

  const new notFound([this.code = 'not_found', this.description]) : status = 404;

  const new tooManyRequests(this.code, [this.description]) : status = 429;

  const new unauthorized([this.code = 'unauthorized', this.description]) : status = 401;

  bool matches(ApiException e) => e.statusCode == status && e.code == code;
}

/// A refusal's body, as `ApiException.toMap` writes it.
Map<String, Object?> _errorSchema(Components components) {
  return components.ref('Error', () {
    return {
      'type': 'object',
      'properties': {
        'error': {'type': 'string', 'description': 'The category, in words.'},
        'code': {'type': 'string', 'description': 'Stable and machine-readable: branch on this.'},
        'reason': {'type': 'string'},
        'message': {'type': 'string'},
        'retryAfter': {'type': 'integer', 'description': 'Seconds, on a 429; also the Retry-After header.'},
      },
      'required': ['error', 'code'],
    };
  });
}

/// The responses for [failures], grouped by status, each listing its codes.
Map<String, Object?> describeFailures(Iterable<Failure> failures, Components components) {
  final byStatus = <int, List<Failure>>{};
  for (final failure in failures) {
    (byStatus[failure.status] ??= []).add(failure);
  }
  return {
    for (final MapEntry(key: status, value: each) in byStatus.entries)
      '$status': {
        'description': [
          for (final failure in each)
            '`${failure.code}`${failure.description == null ? '' : ': ${failure.description}'}',
        ].join('; '),
        'content': {
          'application/json': {
            'schema': {
              'allOf': [
                _errorSchema(components),
                {
                  'properties': {
                    'code': {'enum': each.map((failure) => failure.code).toSet().toList()},
                  },
                },
              ],
            },
          },
        },
      },
  };
}

class _Endpoint<Q, R> implements Endpoint {
  final Future<R> Function(Request, Q) handle;
  final Input<Q>? input;
  final Reply<R> reply;
  final String? summary;
  final List<Failure> errors;

  new(this.handle, {required this.input, required this.reply, this.summary, this.errors = const []});

  @override
  ModelHandler get handler => call;

  @override
  Future<Model?> call(Request request, {Map<String, String>? path}) async {
    try {
      final query = path == null ? Query.of(request) : Query.values(request.url.queryParameters, path: path);
      final read = input == null ? null as Q : input!(query);
      return reply.wrap(await handle(request, read));
    } on ApiException catch (e) {
      assert(_declares(e), 'undeclared ${e.statusCode} ${e.code}: declare it in the route\'s errors');
      rethrow;
    }
  }

  /// A [NoContent] is control flow, not a refusal, and any 400 is the
  /// input's to raise.
  bool _declares(ApiException e) {
    return e is NoContent || (input != null && e.statusCode == 400) || errors.any((failure) => failure.matches(e));
  }

  @override
  Map<String, Object?> operation(Components components, {required String id}) {
    final recording = Query.recording();
    input?.call(recording);
    final parameters = recording.parameters;
    return {
      'operationId': id,
      'summary': ?summary,
      if (parameters.isNotEmpty) 'parameters': [for (final parameter in parameters) parameter.toMap()],
      'responses': {
        ...reply.describe(components),
        ...describeFailures([if (input != null) const Failure.badRequest(), ...errors], components),
      },
    };
  }
}

class _Undeclared implements Endpoint {
  @override
  final ModelHandler handler;
  final String? summary;

  new(this.handler, {this.summary});

  @override
  Future<Model?> call(Request request, {Map<String, String>? path}) => handler(request);

  @override
  Map<String, Object?> operation(Components components, {required String id}) {
    return {
      'operationId': id,
      'summary': ?summary,
      'x-undeclared': true,
      'responses': {
        '200': {'description': 'Not declared yet.'},
      },
    };
  }
}

class _Encoded implements Model {
  final Map<String, dynamic> body;

  const new(this.body);

  @override
  Map<String, dynamic> toMap() => body;
}

class _Json<R> extends Reply<R> {
  final Shape<R> shape;
  final int status;
  final String description;

  const new(this.shape, {required this.status, required this.description});

  @override
  Model wrap(R result) {
    final body = _Encoded((shape.encode(result) as Map).cast<String, dynamic>());
    return switch (status) {
      201 => Created(body),
      202 => Accepted(body),
      _ => body,
    };
  }

  @override
  Map<String, Object?> describe(Components components) => {
    '$status': {
      'description': description,
      'content': {
        'application/json': {'schema': shape.describe(components)},
      },
    },
  };
}

class _Download extends Reply<Model> {
  final String mimeType;
  final String description;

  const new(this.mimeType, {required this.description});

  @override
  Model wrap(Model result) {
    assert(result is Download || result is SeeOther, 'a download answers with a file or a 303, not $result');
    return result;
  }

  @override
  Map<String, Object?> describe(Components components) => {
    '200': {
      'description': description,
      'content': {
        mimeType: {
          'schema': {'type': 'string', 'format': 'binary'},
        },
      },
    },
    '303': {
      'description': 'Too large to answer inline: the file is at `Location`, behind a short-lived link.',
      'headers': {
        'Location': {
          'schema': {'type': 'string', 'format': 'uri'},
        },
      },
    },
  };
}

extension EndpointTables on Router<Handler> {
  /// Registers [table] as [RouteTables.addRoutes] registers a [RouteTable].
  void addEndpoints(EndpointTable table) {
    addRoutes({for (final MapEntry(:key, :value) in table.entries) key: value.handler});
  }
}

/// The OpenAPI 3.1 document for [table], attached at [prefix]. [everywhere]
/// are the refusals any route of the surface can answer with, before its
/// handler runs: the authentication's and the rate limit's.
Map<String, Object?> openApiDocument(
  EndpointTable table, {
  required String prefix,
  required String title,
  required String version,
  String? description,
  Map<String, Object?> securitySchemes = const {},
  List<Failure> everywhere = const [],
}) {
  final components = Components();
  final paths = <String, Map<String, Object?>>{};
  for (final MapEntry(key: (route, verb), value: endpoint) in table.entries) {
    final path = '$prefix${route == '/' ? '' : route}'.replaceAllMapped(RegExp(r':(\w+)'), (m) => '{${m[1]}}');
    final operation = endpoint.operation(components, id: _operationId(verb, route));
    // a segment the route has but its input never read, as on an undeclared
    // route, is still a parameter the path requires
    final parameters = [...?operation['parameters'] as List?];
    for (final match in RegExp(r':(\w+)').allMatches(route)) {
      if (parameters.any((parameter) => (parameter as Map)['name'] == match[1])) continue;
      parameters.add(Parameter(match[1]!, location: 'path', required: true, schema: const {'type': 'string'}).toMap());
    }
    (paths[path.isEmpty ? '/' : path] ??= {})[verb.name] = {
      ...operation,
      if (parameters.isNotEmpty) 'parameters': parameters,
      'responses': {
        ...operation['responses'] as Map<String, Object?>,
        ...describeFailures(everywhere, components),
      },
    };
  }
  return {
    'openapi': '3.1.0',
    'info': {'title': title, 'version': version, 'description': ?description},
    'paths': paths,
    'components': {
      'schemas': components.schemas,
      if (securitySchemes.isNotEmpty) 'securitySchemes': securitySchemes,
    },
    if (securitySchemes.isNotEmpty)
      'security': [
        {for (final name in securitySchemes.keys) name: const <String>[]},
      ],
  };
}

/// `getWorkoutsWorkoutId` from `GET /workouts/:workoutId`.
String _operationId(Method verb, String route) {
  final words = route.split(RegExp(r'[/:\-]')).where((word) => word.isNotEmpty);
  return [verb.name, for (final word in words) '${word[0].toUpperCase()}${word.substring(1)}'].join();
}
