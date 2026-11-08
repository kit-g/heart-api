import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/connections.dart`. A path names a
/// connection by its `connectionId`; these cover the happy paths, an id that
/// isn't the caller's, and the validation branches that map bad input to 400.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const id = '01900000-0000-7000-8000-0000000000c1';

  Connection sample() => Connection(
    targetId: 't1',
    role: ConnectionRole.coach,
    domain: ConnectionDomain.fitness,
    status: ConnectionStatus.pending,
    createdAt: DateTime.utc(2026, 1, 1),
    connectionId: id,
  );

  void known() {
    when(
      app.db.getConnectionById(actorId: anyNamed('actorId'), connectionId: anyNamed('connectionId')),
    ).thenAnswer((_) async => null);
    when(app.db.getConnectionById(actorId: 'u1', connectionId: id)).thenAnswer((_) async => sample());
  }

  group('GET /connections', () {
    test('lists connections and applies a role filter from the query', () async {
      when(app.db.getConnections(any, roleFilter: anyNamed('roleFilter'))).thenAnswer((_) async => [sample()]);

      final res = await app.send('GET', '/connections?role=COACH');
      expect(res.status, 200);
      final connection = ((jsonDecode(res.body) as Map)['connections'] as List).single as Map;
      expect(connection['connectionId'], id);
      expect(connection['role'], 'coach', reason: 'words in lower case, as invitations answer them');
      expect(connection['domain'], 'fitness');
      expect(connection.containsKey('id'), isFalse);
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
          'role': 'PEER',
          'domain': 'fitness',
        },
      );
      expect(res.status, 200);
      verify(
        app.db.createConnection(
          initiatorId: 'u1',
          targetId: 't1',
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
        ),
      ).called(1);
    });

    for (final role in ['COACH', 'STUDENT']) {
      test('a $role connection needs an invitation', () async {
        final res = await app.send('POST', '/connections', body: {'targetId': 't1', 'role': role, 'domain': 'fitness'});
        expect(res.status, 400);
        expect(res.body, contains('invitation_required'));
      });
    }

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
    test('ends the connection the id names, from the caller\'s side (204)', () async {
      known();
      when(
        app.db.deleteConnection(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
        ),
      ).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/connections/$id');
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

    test('an id that was never one, the old composite form included, is a 404', () async {
      for (final path in ['not-a-valid-id', 't1%7CCOACH%7Cfitness']) {
        expect((await app.send('DELETE', '/connections/$path')).status, 404, reason: path);
      }
      verifyZeroInteractions(app.db);
    });

    test('a connection the caller isn\'t on is a 404', () async {
      known();
      final res = await app.send('DELETE', '/connections/01900000-0000-7000-8000-0000000000c2');
      expect(res.status, 404);
    });
  });

  group('PUT /connections/:connectionId', () {
    test('changes status from the body', () async {
      known();
      when(
        app.db.changeConnectionStatus(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
          newStatus: anyNamed('newStatus'),
        ),
      ).thenAnswer((_) async => sample());

      final res = await app.send('PUT', '/connections/$id', body: {'status': 'active'});
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
      expect((await app.send('PUT', '/connections/$id', body: {})).status, 400);
    });

    test('rejects an unknown status with 400 instead of reading it as pending', () async {
      final res = await app.send('PUT', '/connections/$id', body: {'status': 'nonsense'});
      expect(res.status, 400);
    });

    test('a malformed connection id is a 404', () async {
      expect((await app.send('PUT', '/connections/bogus', body: {'status': 'active'})).status, 404);
    });

    test('maps an illegal status transition (StateError) to 400', () async {
      known();
      when(
        app.db.changeConnectionStatus(
          actorId: anyNamed('actorId'),
          targetId: anyNamed('targetId'),
          role: anyNamed('role'),
          domain: anyNamed('domain'),
          newStatus: anyNamed('newStatus'),
        ),
      ).thenThrow(StateError('cannot transition'));

      final res = await app.send('PUT', '/connections/$id', body: {'status': 'active'});
      expect(res.status, 400);
    });
  });

  test('a share nobody has heard of is refused, naming it, before anything changes', () async {
    final res = await app.send(
      'PUT',
      '/connections/$id/shares',
      body: {
        'shares': ['everything'],
      },
    );

    expect(res.status, 400);
    expect(res.body, contains('everything'));
    verifyZeroInteractions(app.db);
  });
}
