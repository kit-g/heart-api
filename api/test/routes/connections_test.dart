import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/connections.dart`. Connections are keyed
/// by a composite `targetId|role|domain` id; these cover the happy paths plus
/// the id-parsing and validation branches that map bad input to 400.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  Connection sample() => Connection(
    targetId: 't1',
    role: ConnectionRole.coach,
    domain: ConnectionDomain.fitness,
    status: ConnectionStatus.pending,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  group('GET /connections', () {
    test('lists connections and applies a role filter from the query', () async {
      when(app.db.getConnections(any, roleFilter: anyNamed('roleFilter'))).thenAnswer((_) async => [sample()]);

      final res = await app.send('GET', '/connections?role=COACH');
      expect(res.status, 200);
      expect(jsonDecode(res.body), hasLength(1));
      verify(app.db.getConnections('u1', roleFilter: ConnectionRole.coach)).called(1);
    });

    test('passes a null role filter when the query is empty', () async {
      when(app.db.getConnections(any, roleFilter: anyNamed('roleFilter'))).thenAnswer((_) async => const []);

      await app.send('GET', '/connections');
      verify(app.db.getConnections('u1', roleFilter: null)).called(1);
    });
  });

  group('POST /connections', () {
    test('creates a connection from the body', () async {
      when(
        app.db.createConnection(
          initiatorId: anyNamed('initiatorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
        ),
      ).thenAnswer((_) async => sample());

      final res = await app.send(
        'POST',
        '/connections',
        body: {
          'targetId': 't1',
          'role': 'COACH',
          'domain': 'fitness',
        },
      );
      expect(res.status, 200);
      verify(
        app.db.createConnection(
          initiatorId: 'u1',
          targetId: 't1',
          role: ConnectionRole.coach,
          domain: ConnectionDomain.fitness,
        ),
      ).called(1);
    });

    test('rejects connecting to yourself with 400', () async {
      final res = await app.send(
        'POST',
        '/connections',
        body: {'targetId': 'u1', 'role': 'PEER', 'domain': 'fitness'},
      );
      expect(res.status, 400);
    });

    // These used to be coerced — a typo'd role quietly produced a peer
    // connection and a 200.
    test('rejects an unknown role with 400', () async {
      final res = await app.send(
        'POST',
        '/connections',
        body: {'targetId': 't1', 'role': 'SENSEI', 'domain': 'fitness'},
      );
      expect(res.status, 400);
    });

    test('rejects an unknown domain with 400', () async {
      final res = await app.send(
        'POST',
        '/connections',
        body: {'targetId': 't1', 'role': 'PEER', 'domain': 'yoga'},
      );
      expect(res.status, 400);
    });

    test('rejects a missing targetId with 400', () async {
      expect((await app.send('POST', '/connections', body: {'role': 'PEER', 'domain': 'fitness'})).status, 400);
    });
  });

  group('DELETE /connections/:connectionId', () {
    test('parses the composite id and deletes (204)', () async {
      when(
        app.db.deleteConnection(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
        ),
      ).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/connections/t1%7CCOACH%7Cfitness');
      expect(res.status, 204);
      verify(
        app.db.deleteConnection(
          actorId: 'u1',
          targetId: 't1',
          role: ConnectionRole.coach,
          domain: ConnectionDomain.fitness,
        ),
      ).called(1);
    });

    test('rejects a malformed id with 400', () async {
      expect((await app.send('DELETE', '/connections/not-a-valid-id')).status, 400);
    });
  });

  group('PUT /connections/:connectionId', () {
    test('changes status from the body', () async {
      when(
        app.db.changeConnectionStatus(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
          newStatus: anyNamed('newStatus'),
        ),
      ).thenAnswer((_) async => sample());

      final res = await app.send('PUT', '/connections/t1%7CCOACH%7Cfitness', body: {'status': 'active'});
      expect(res.status, 200);
      verify(
        app.db.changeConnectionStatus(
          actorId: 'u1',
          targetId: 't1',
          role: ConnectionRole.coach,
          domain: ConnectionDomain.fitness,
          newStatus: ConnectionStatus.active,
        ),
      ).called(1);
    });

    test('rejects a missing status with 400', () async {
      expect((await app.send('PUT', '/connections/t1%7CCOACH%7Cfitness', body: {})).status, 400);
    });

    test('rejects an unknown status with 400 instead of reading it as pending', () async {
      final res = await app.send('PUT', '/connections/t1%7CCOACH%7Cfitness', body: {'status': 'nonsense'});
      expect(res.status, 400);
    });

    test('rejects a malformed connection id with 400', () async {
      expect((await app.send('PUT', '/connections/bogus', body: {'status': 'active'})).status, 400);
    });

    test('maps an illegal status transition (StateError) to 400', () async {
      when(
        app.db.changeConnectionStatus(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
          newStatus: anyNamed('newStatus'),
        ),
      ).thenThrow(StateError('cannot transition'));

      final res = await app.send('PUT', '/connections/t1%7CCOACH%7Cfitness', body: {'status': 'active'});
      expect(res.status, 400);
    });
  });
}
