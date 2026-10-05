import 'dart:convert';

/// The MCP revision served statelessly, with per-request `_meta`.
const modernVersion = '2026-07-28';

/// Revisions served to clients that open with `initialize`, newest first.
/// Stateless in all of them: no session id is minted, GET and DELETE are 405.
const legacyVersions = ['2025-11-25', '2025-06-18', '2025-03-26'];

const supportedVersions = [modernVersion, ...legacyVersions];

const metaProtocolVersion = 'io.modelcontextprotocol/protocolVersion';
const metaClientInfo = 'io.modelcontextprotocol/clientInfo';
const metaServerInfo = 'io.modelcontextprotocol/serverInfo';

/// JSON-RPC and MCP error codes this server answers with.
abstract final class RpcCode {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
  static const headerMismatch = -32020;
  static const unsupportedProtocolVersion = -32022;
}

/// A JSON-RPC failure, with the HTTP status the transport gives it.
class RpcError implements Exception {
  final int code;
  final String message;
  final int status;
  final Object? data;

  const new(this.code, this.message, {this.status = 200, this.data});

  Map<String, dynamic> toJson(Object? id) {
    return {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message, 'data': ?data},
    };
  }
}

/// A header value as the transport encodes it: plain, or the Base64 sentinel
/// `=?base64?…?=` for values that aren't safe as plain ASCII.
String decodeHeaderValue(String value) {
  if (value.startsWith('=?base64?') && value.endsWith('?=')) {
    return utf8.decode(base64.decode(value.substring(9, value.length - 2)));
  }
  return value;
}
