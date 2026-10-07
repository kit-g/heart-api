import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fetches a small JSON document from a URL a stranger chose: a client's
/// metadata document, or its key set. Throws [DocumentFetchError] for
/// anything that isn't one, or isn't safe to ask for.
typedef JsonFetch = Future<Map<String, dynamic>> Function(Uri uri);

class DocumentFetchError implements Exception {
  final String reason;

  const new(this.reason);

  @override
  String toString() => 'DocumentFetchError: $reason';
}

/// The real [JsonFetch], guarded the way a server-side request to an
/// arbitrary URL has to be:
///
/// - HTTPS only, on the default port;
/// - the host must resolve to public addresses only: no loopback, private,
///   link-local, carrier-grade NAT or unique-local ranges, checked after
///   resolution so a hostname can't smuggle one in;
/// - no redirects, a short timeout and a body cap.
///
/// The address check and the connection resolve separately, so a rebinding
/// DNS server could still race it. The function has no network of its own
/// behind it (no VPC, no instance metadata service), which is what makes that
/// residual risk acceptable.
Future<Map<String, dynamic>> guardedJsonFetch(
  Uri uri, {
  Duration timeout = const Duration(seconds: 5),
  int maxBytes = 16 * 1024,
}) async {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.hasPort && uri.port != 443 || uri.userInfo.isNotEmpty) {
    throw const DocumentFetchError('only plain https URLs');
  }
  final List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
  } on Object {
    throw const DocumentFetchError('host does not resolve');
  }
  if (addresses.isEmpty || addresses.any(isNonPublicAddress)) {
    throw const DocumentFetchError('host is not on the public internet');
  }

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw DocumentFetchError('answered ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) throw const DocumentFetchError('document too large');
    }
    return switch (jsonDecode(utf8.decode(bytes))) {
      final Map<String, dynamic> json => json,
      _ => throw const DocumentFetchError('not a JSON object'),
    };
  } on DocumentFetchError {
    rethrow;
  } on Object {
    throw const DocumentFetchError('could not be fetched');
  } finally {
    client.close(force: true);
  }
}

/// True for any address that isn't routable on the public internet.
bool isNonPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) return true;
  final b = address.rawAddress;
  return switch (address.type) {
    InternetAddressType.IPv4 =>
      b[0] == 0 ||
          b[0] == 10 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          b[0] >= 224,
    InternetAddressType.IPv6 =>
      b.every((byte) => byte == 0) ||
          (b[0] & 0xfe) == 0xfc ||
          (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) ||
          // IPv4-mapped (::ffff:a.b.c.d): judged as the IPv4 it carries
          (b.sublist(0, 10).every((byte) => byte == 0) &&
              b[10] == 0xff &&
              b[11] == 0xff &&
              isNonPublicAddress(InternetAddress.fromRawAddress(b.sublist(12)))),
    _ => true,
  };
}
