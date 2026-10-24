import 'dart:convert';

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/mcp/protocol.dart';
import 'package:heart/mcp/tools.dart';
import 'package:heart/mcp/widgets.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/tokens.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart/oauth/protocol.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('Mcp');

/// Who this server is, as a host shows it on the connector's page; the
/// description, website and icons are read since 2025-11-25. [writes] is
/// whether this credential is offered the template writes.
Map<String, dynamic> _serverInfo({required bool writes}) {
  return {
    'name': 'heart',
    'title': 'Heart',
    'version': '1.0.0',
    'description': switch (writes) {
      true =>
        'Your Heart workout log: workouts, sets, templates, programs and goals; templates can be built with '
            'your permission.',
      false => 'Your Heart workout log: workouts, sets, templates, programs and goals, read-only.',
    },
    'websiteUrl': 'https://heart-of.me',
    'icons': [
      {
        'src': 'https://heart-of.me/assets/favicon.png',
        'mimeType': 'image/png',
        'sizes': ['256x256'],
      },
    ],
  };
}

/// How long a client may cache the tool list and discovery result.
const _listTtl = Duration(hours: 1);

/// The MCP endpoint: one JSON-RPC message per POST, answered with plain JSON.
///
/// Serves both eras on one endpoint. A request carrying
/// `io.modelcontextprotocol/protocolVersion` in `_meta` is modern (2026-07-28):
/// headers are checked against the body and results carry `resultType`. One
/// that opens with `initialize` is legacy, served statelessly: no session id
/// is ever minted, so every request stands alone either way.
///
/// A request from a browser origin the API doesn't trust is refused outright.
/// Authenticated with a personal access token. Only data calls (`tools/call`)
/// count against the account's rate limits; a host repeats the handshake and
/// the tool list at the start of every conversation, and the resources are
/// static widget pages, the same for every account.
Future<Response> mcpEndpoint(Request request) async {
  // DNS-rebinding defence: hosts call from their servers and send no Origin;
  // a browser page that names one has to be one this API already trusts.
  if (request.headers['origin']?.firstOrNull case final origin? when !request.config.allowedOrigins.contains(origin)) {
    return _error(null, const .new(.invalidRequest, 'Origin not allowed', status: 403));
  }

  final Map<String, dynamic> message;
  try {
    message = switch (jsonDecode(await request.readAsString())) {
      final Map<String, dynamic> m => m,
      _ => throw const RpcError(.invalidRequest, 'Expected one JSON-RPC message', status: 400),
    };
  } on FormatException {
    return _error(null, const .new(.parseError, 'Body is not JSON', status: 400));
  } on RpcError catch (e) {
    return _error(null, e);
  }

  final id = message['id'];
  final method = message['method'];
  if (method is! String || message['jsonrpc'] != '2.0') {
    return _error(id, const .new(.invalidRequest, 'Expected a JSON-RPC 2.0 request', status: 400));
  }
  final params = switch (message['params']) {
    final Map<String, dynamic> p => p,
    null => const <String, dynamic>{},
    _ => null,
  };
  if (params == null) return _error(id, const .new(.invalidParams, 'params must be an object'));

  final meta = switch (params['_meta']) {
    final Map<String, dynamic> m => m,
    _ => const <String, dynamic>{},
  };
  final modern = meta[metaProtocolVersion];
  // A legacy client names itself once, in initialize; a modern one in every
  // request's _meta.
  final client = switch ((method, params['clientInfo'], meta[metaClientInfo])) {
    ('initialize', {'name': final String name}, _) => name,
    (_, _, {'name': final String name}) => name,
    _ => null,
  };
  final route = switch ((method, params['name'])) {
    ('tools/call', final String tool) => 'tools/call:$tool',
    _ => method,
  };

  final oauth = request.config.oauth;
  final check = await checkToken(
    request,
    count: method == 'tools/call',
    resource: oauth?.mcpResource,
    // how a host that has no token learns where to get one (RFC 9728)
    challenge: [
      if (oauth != null) ...[
        AuthenticationParameter('resource_metadata', oauth.mcpResourceMetadata.toString()),
        AuthenticationParameter('scope', ([...supportedScopes]..sort()).join(' ')),
      ],
    ],
  );
  switch (check) {
    case TokenRefused(:final response):
      logApiUsage(request, surface: 'mcp', status: response.statusCode, route: route, client: client);
      return response;
    case TokenAccepted(:final use):
      request.user = User(id: use.userId);
      final response = await _respond(request, use: use, id: id, method: method, params: params, modern: modern);
      logApiUsage(request, surface: 'mcp', status: response.statusCode, use: use, route: route, client: client);
      return response;
  }
}

Future<Response> _respond(
  Request request, {
  required TokenUse use,
  required Object? id,
  required String method,
  required Map<String, dynamic> params,
  required Object? modern,
}) async {
  try {
    if (modern != null) _checkModern(request, version: modern, method: method, params: params);

    // A notification (no id) is accepted and has nothing to answer.
    if (id == null) return .new(202);

    final writes = use.offersWrites;
    if (method == 'tools/call') {
      if (_scopeRefusal(request, use: use, id: id, params: params, modern: modern) case final Response refused) {
        return refused;
      }
    }

    final result = switch (method) {
      'initialize' => _initialize(params, writes: writes),
      'server/discover' => _discover(writes: writes),
      'ping' when modern == null => <String, dynamic>{},
      'tools/list' => {
        'tools': [
          for (final tool in tools)
            if (tool.scope == .read || writes) tool.toJson(),
        ],
        if (modern != null) ...{'ttlMs': _listTtl.inMilliseconds, 'cacheScope': 'private'},
      },
      'tools/call' => await _callTool(request, params),
      'resources/list' => {
        'resources': [for (final widget in widgets) widget.toResource()],
        if (modern != null) ...{'ttlMs': _listTtl.inMilliseconds, 'cacheScope': 'public'},
      },
      // advertising resources makes some clients ask for templates too
      'resources/templates/list' => {
        'resourceTemplates': const <Object>[],
        if (modern != null) ...{'ttlMs': _listTtl.inMilliseconds, 'cacheScope': 'public'},
      },
      'resources/read' => {
        'contents': [_widgetOf(params).toContents()],
        if (modern != null) ...{'ttlMs': _listTtl.inMilliseconds, 'cacheScope': 'public'},
      },
      _ => throw RpcError(.methodNotFound, 'Method not found: $method', status: 404),
    };

    return _json(200, {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        ...result,
        if (modern != null) ...{
          'resultType': 'complete',
          '_meta': {metaServerInfo: _serverInfo(writes: writes)},
        },
      },
    });
  } on RpcError catch (e) {
    return _error(id, e);
  } catch (e, st) {
    _logger.severe('MCP $method failed', e, st);
    return _error(id, const .new(.internalError, 'Internal error', status: 500));
  }
}

/// A modern request must name a version this server speaks, and its headers
/// must say what its body says.
void _checkModern(
  Request request, {
  required Object version,
  required String method,
  required Map<String, dynamic> params,
}) {
  if (version != modernVersion) {
    throw RpcError(
      .unsupportedProtocolVersion,
      'Unsupported protocol version',
      status: 400,
      data: {'supported': supportedVersions, 'requested': version},
    );
  }
  String? header(String name) => request.headers[name]?.firstOrNull;

  void expect(String name, Object? body) {
    final value = header(name);
    if (value == null) throw RpcError(.headerMismatch, 'Header mismatch: $name is missing', status: 400);
    if (decodeHeaderValue(value) != body) {
      throw RpcError(
        .headerMismatch,
        "Header mismatch: $name header value '$value' does not match body value '$body'",
        status: 400,
      );
    }
  }

  expect('mcp-protocol-version', version);
  expect('mcp-method', method);
  switch (method) {
    case 'tools/call' || 'prompts/get':
      expect('mcp-name', params['name']);
    case 'resources/read':
      expect('mcp-name', params['uri']);
  }
}

Map<String, dynamic> _initialize(Map<String, dynamic> params, {required bool writes}) {
  final requested = params['protocolVersion'];
  return {
    'protocolVersion': legacyVersions.contains(requested) ? requested : legacyVersions.first,
    'capabilities': {
      'tools': {'listChanged': false},
      'resources': {'listChanged': false},
    },
    'serverInfo': _serverInfo(writes: writes),
    'instructions': instructionsFor(writes: writes),
  };
}

Map<String, dynamic> _discover({required bool writes}) {
  return {
    'supportedVersions': supportedVersions,
    'capabilities': {'tools': <String, dynamic>{}, 'resources': <String, dynamic>{}},
    'instructions': instructionsFor(writes: writes),
    'ttlMs': _listTtl.inMilliseconds,
    // the instructions differ by credential: a grant is told about the writes
    'cacheScope': 'private',
  };
}

/// A widget page by its `ui://` URI. An unknown one is invalid params, the
/// code 2026-07-28 gives a missing resource; to a 2025 client, whose spec
/// said -32002, it is still an error naming the URI.
McpWidget _widgetOf(Map<String, dynamic> params) {
  return switch (widgetsByUri[params['uri']]) {
    final McpWidget widget => widget,
    null => throw RpcError(.invalidParams, 'Resource not found', data: {'uri': params['uri']}),
  };
}

/// A tool call the token's scopes don't cover, refused before it runs: `403`
/// with the `insufficient_scope` challenge, which is what makes a compliant
/// host ask the user to widen the grant and try again (the MCP authorization
/// spec's step-up). The body is a tool error saying the same, with the
/// challenge again under `_meta["mcp/www_authenticate"]`, where ChatGPT looks
/// for it. Null when the call may go ahead, or names no tool this server has.
Response? _scopeRefusal(
  Request request, {
  required TokenUse use,
  required Object? id,
  required Map<String, dynamic> params,
  required Object? modern,
}) {
  final tool = switch (params['name']) {
    final String name => toolsByName[name],
    _ => null,
  };
  if (tool == null || use.scopes.contains(tool.scope.value)) return null;

  final message = switch (use.clientId) {
    // a personal token is read-only for good: there is nothing to widen
    null =>
      '${tool.name} needs a connection with the ${tool.scope.value} permission. Personal tokens only read; '
          'connect Heart to this assistant by signing in to change templates.',
    _ =>
      '${tool.name} needs the ${tool.scope.value} permission, which this connection was made without. Ask the user '
          'to reconnect Heart to this assistant, which grants it.',
  };
  final oauth = request.config.oauth;
  final challenge = [
    if (oauth != null) AuthenticationParameter('resource_metadata', oauth.mcpResourceMetadata.toString()),
  ];
  final headers = insufficientScopeHeaders(held: use.scopes, needed: tool.scope, challenge: challenge);
  return .new(
    403,
    headers: headers,
    body: .fromString(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': message},
          ],
          'isError': true,
          '_meta': {
            'mcp/www_authenticate': [...?headers['www-authenticate']],
            if (modern != null) metaServerInfo: _serverInfo(writes: use.offersWrites),
          },
          if (modern != null) 'resultType': 'complete',
        },
      }),
      mimeType: .json,
    ),
  );
}

/// Said beside every result a card can draw. The server can't tell whether
/// this host draws cards, so it says what to do when one does: a host that
/// shows the card and has the model restate it shows the workout twice.
const _shownAsCard =
    'A host that draws Heart cards shows this result to the user as a card. If it does, the user already sees '
    "it: don't restate it, answer what they asked. Weights here are in kg and distances in km; give them in "
    'unitSystem.';

/// The units the user logs in, as `get_profile` names them.
Future<String> _unitSystem(Request request) async {
  final user = await request.profileService.getProfile(request.userId);
  return user?.settings.unitSystem?.name ?? 'metric';
}

Future<Map<String, dynamic>> _callTool(Request request, Map<String, dynamic> params) async {
  final tool = switch (params['name']) {
    final String name => toolsByName[name],
    _ => null,
  };
  if (tool == null) throw RpcError(.invalidParams, 'Unknown tool: ${params['name']}');
  final arguments = switch (params['arguments']) {
    final Map<String, dynamic> a => a,
    null => const <String, dynamic>{},
    _ => throw const RpcError(.invalidParams, 'arguments must be an object'),
  };

  try {
    final result = await tool.run(request, arguments);
    // a card draws in the user's units, and the model answers in them
    final structured = switch (tool.widget) {
      null => result,
      _ => {...result, 'unitSystem': await _unitSystem(request)},
    };
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
        if (tool.widget != null) const {'type': 'text', 'text': _shownAsCard},
      ],
      'structuredContent': structured,
      'isError': false,
    };
  } on ToolError catch (e) {
    return {
      'content': [
        {'type': 'text', 'text': e.message},
      ],
      'isError': true,
    };
  }
}

extension on TokenUse {
  /// Whether this credential is shown the write tools. An OAuth grant is,
  /// whatever it holds: a host that calls one without the scope is told to
  /// widen the grant, which is the only way it learns the writes exist. A
  /// personal token never is. It stays read-only (`docs/2026-09-23.developer-api.md`,
  /// *Phase 4*), so a write would only ever be refused.
  bool get offersWrites => clientId != null;
}

Response _json(int status, Map<String, dynamic> body) {
  return .new(status, body: .fromString(jsonEncode(body), mimeType: .json));
}

Response _error(Object? id, RpcError e) => _json(e.status, e.toJson(id));

/// GET and DELETE belong to the session-based transport this server doesn't
/// run: the 2025 revisions' standalone stream and session teardown.
Future<Response> mcpMethodNotAllowed(Request request) async {
  return .new(
    405,
    headers: .build((headers) => headers.allow = {.post}),
  );
}

/// RFC 9728 protected resource metadata: which authorization server issues
/// tokens for this MCP server, and for what.
Future<Response> mcpResourceMetadata(Request request) async {
  final oauth = request.config.oauth;
  if (oauth == null) return Response.notFound();
  return _json(200, {
    'resource': oauth.mcpResource,
    'authorization_servers': [oauth.issuer.toString()],
    'scopes_supported': [...supportedScopes],
    'bearer_methods_supported': ['header'],
    'resource_name': 'Heart',
  });
}
