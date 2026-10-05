import 'dart:convert';

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/mcp/protocol.dart';
import 'package:heart/mcp/tools.dart';
import 'package:heart/middleware/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('Mcp');

const _serverInfo = {'name': 'heart', 'title': 'Heart', 'version': '1.0.0'};

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
/// the tool list at the start of every conversation.
Future<Response> mcpEndpoint(Request request) async {
  // DNS-rebinding defence: hosts call from their servers and send no Origin;
  // a browser page that names one has to be one this API already trusts.
  if (request.headers['origin']?.firstOrNull case final origin? when !request.config.allowedOrigins.contains(origin)) {
    return _error(null, const RpcError(RpcCode.invalidRequest, 'Origin not allowed', status: 403));
  }

  final Map<String, dynamic> message;
  try {
    message = switch (jsonDecode(await request.readAsString())) {
      final Map<String, dynamic> m => m,
      _ => throw const RpcError(RpcCode.invalidRequest, 'Expected one JSON-RPC message', status: 400),
    };
  } on FormatException {
    return _error(null, const RpcError(RpcCode.parseError, 'Body is not JSON', status: 400));
  } on RpcError catch (e) {
    return _error(null, e);
  }

  final id = message['id'];
  final method = message['method'];
  if (method is! String || message['jsonrpc'] != '2.0') {
    return _error(id, const RpcError(RpcCode.invalidRequest, 'Expected a JSON-RPC 2.0 request', status: 400));
  }
  final params = switch (message['params']) {
    final Map<String, dynamic> p => p,
    null => const <String, dynamic>{},
    _ => null,
  };
  if (params == null) return _error(id, const RpcError(RpcCode.invalidParams, 'params must be an object'));

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

  final check = await checkToken(request, count: method == 'tools/call');
  switch (check) {
    case TokenRefused(:final response):
      logApiUsage(request, surface: 'mcp', status: response.statusCode, route: route, client: client);
      return response;
    case TokenAccepted(:final use):
      request.user = User(id: use.userId);
      final response = await _respond(request, id: id, method: method, params: params, modern: modern);
      logApiUsage(request, surface: 'mcp', status: response.statusCode, use: use, route: route, client: client);
      return response;
  }
}

Future<Response> _respond(
  Request request, {
  required Object? id,
  required String method,
  required Map<String, dynamic> params,
  required Object? modern,
}) async {
  try {
    if (modern != null) _checkModern(request, version: modern, method: method, params: params);

    // A notification (no id) is accepted and has nothing to answer.
    if (id == null) return Response(202);

    final result = switch (method) {
      'initialize' => _initialize(params),
      'server/discover' => _discover(),
      'ping' when modern == null => <String, dynamic>{},
      'tools/list' => {
        'tools': [for (final tool in tools) tool.toJson()],
        if (modern != null) ...{'ttlMs': _listTtl.inMilliseconds, 'cacheScope': 'private'},
      },
      'tools/call' => await _callTool(request, params),
      _ => throw RpcError(RpcCode.methodNotFound, 'Method not found: $method', status: 404),
    };

    return _json(200, {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        ...result,
        if (modern != null) ...{
          'resultType': 'complete',
          '_meta': {metaServerInfo: _serverInfo},
        },
      },
    });
  } on RpcError catch (e) {
    return _error(id, e);
  } catch (e, st) {
    _logger.severe('MCP $method failed', e, st);
    return _error(id, const RpcError(RpcCode.internalError, 'Internal error', status: 500));
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
      RpcCode.unsupportedProtocolVersion,
      'Unsupported protocol version',
      status: 400,
      data: {'supported': supportedVersions, 'requested': version},
    );
  }
  String? header(String name) => request.headers[name]?.firstOrNull;

  void expect(String name, Object? body) {
    final value = header(name);
    if (value == null) throw RpcError(RpcCode.headerMismatch, 'Header mismatch: $name is missing', status: 400);
    if (decodeHeaderValue(value) != body) {
      throw RpcError(
        RpcCode.headerMismatch,
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

Map<String, dynamic> _initialize(Map<String, dynamic> params) {
  final requested = params['protocolVersion'];
  return {
    'protocolVersion': legacyVersions.contains(requested) ? requested : legacyVersions.first,
    'capabilities': {
      'tools': {'listChanged': false},
    },
    'serverInfo': _serverInfo,
    'instructions': instructions,
  };
}

Map<String, dynamic> _discover() {
  return {
    'supportedVersions': supportedVersions,
    'capabilities': {'tools': <String, dynamic>{}},
    'instructions': instructions,
    'ttlMs': _listTtl.inMilliseconds,
    'cacheScope': 'public',
  };
}

Future<Map<String, dynamic>> _callTool(Request request, Map<String, dynamic> params) async {
  final tool = switch (params['name']) {
    final String name => toolsByName[name],
    _ => null,
  };
  if (tool == null) throw RpcError(RpcCode.invalidParams, 'Unknown tool: ${params['name']}');
  final arguments = switch (params['arguments']) {
    final Map<String, dynamic> a => a,
    null => const <String, dynamic>{},
    _ => throw const RpcError(RpcCode.invalidParams, 'arguments must be an object'),
  };

  try {
    final structured = await tool.run(request, arguments);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
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

Response _json(int status, Map<String, dynamic> body) {
  return Response(status, body: Body.fromString(jsonEncode(body), mimeType: MimeType.json));
}

Response _error(Object? id, RpcError e) => _json(e.status, e.toJson(id));

/// GET and DELETE belong to the session-based transport this server doesn't
/// run: the 2025 revisions' standalone stream and session teardown.
Future<Response> mcpMethodNotAllowed(Request request) async {
  return Response(
    405,
    headers: Headers.build((headers) => headers.allow = {Method.post}),
  );
}
