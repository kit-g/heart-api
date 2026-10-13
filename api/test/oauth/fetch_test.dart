import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:heart/oauth/fetch.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;

  new(super.stream, this.statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers extends Mock implements HttpHeaders;

class _Request extends Mock implements HttpClientRequest {
  final HttpClientResponse response;

  new(this.response);

  @override
  HttpHeaders get headers => _Headers();

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Mock implements HttpClient {
  final HttpClientRequest request;
  bool forceClosed = false;

  new(this.request);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;

  @override
  void close({bool force = false}) => forceClosed = force;
}

void main() {
  // A numeric public address avoids DNS and all HTTP I/O is intercepted.
  final uri = Uri.parse('https://93.184.216.34/metadata');

  Future<Map<String, dynamic>> fetch(_Client client, {int maxBytes = 1024}) => HttpOverrides.runZoned(
    () => guardedJsonFetch(uri, timeout: const Duration(milliseconds: 100), maxBytes: maxBytes),
    createHttpClient: (_) => client,
  );

  test('a rejected response is never drained', () async {
    var listened = false;
    final body = StreamController<List<int>>(onListen: () => listened = true);
    final client = _Client(_Request(_Response(body.stream, 404)));
    await expectLater(
      fetch(client),
      throwsA(isA<DocumentFetchError>().having((e) => e.reason, 'reason', 'answered 404')),
    );
    expect(listened, isFalse);
    expect(client.forceClosed, isTrue);
    unawaited(body.close());
  });

  test('the deadline bounds a body that continuously makes progress', () async {
    final body = StreamController<List<int>>();
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) => body.add([32]));
    final client = _Client(_Request(_Response(body.stream, 200)));
    try {
      await expectLater(fetch(client).timeout(const Duration(seconds: 2)), throwsA(isA<DocumentFetchError>()));
      expect(client.forceClosed, isTrue);
    } finally {
      timer.cancel();
      await body.close();
    }
  });

  test('enforces the body cap and closes the client', () async {
    final client = _Client(_Request(_Response(Stream.value(utf8.encode('{"client_name":"too long"}')), 200)));
    await expectLater(fetch(client, maxBytes: 4), throwsA(isA<DocumentFetchError>()));
    expect(client.forceClosed, isTrue);
  });

  test('a bounded JSON object still succeeds', () async {
    final client = _Client(_Request(_Response(Stream.value(utf8.encode('{"client_name":"Heart"}')), 200)));
    expect(await fetch(client), {'client_name': 'Heart'});
    expect(client.forceClosed, isTrue);
  });
}
