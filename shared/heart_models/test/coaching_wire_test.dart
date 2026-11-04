import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// What a client receives for [model]: the API answers with `jsonEncode(model.toMap())`
/// (`api/lib/core/response.dart`), and the app decodes it.
Map<String, dynamic> wire(Model model) => jsonDecode(jsonEncode(model.toMap())) as Map<String, dynamic>;

/// [model] written, sent and read back with [read] writes what it wrote.
void expectRoundTrip<T extends Model>(T model, T Function(Map) read) {
  expect(read(wire(model)).toMap(), wire(model));
}

void main() {
  const connection = '01900000-0000-7000-8000-000000000001';
  const program = '01900000-0000-7000-8000-000000000002';
  const session = '01900000-0000-7000-8000-000000000003';
  final at = DateTime.utc(2026, 11, 1, 9, 30);
  final later = DateTime.utc(2026, 11, 2, 18);

  group('PushSettings', () {
    final settings = PushSettings(
      topics: [
        PushSetting(
          topic: 'coaching.message',
          group: 'coaching',
          name: 'Messages',
          description: 'When someone writes to you',
          delivery: 'off',
          options: ['instant', 'off'],
        ),
      ],
      forPeople: [(topic: 'coaching.workout_digest', connectionId: 'c', delivery: 'off')],
    );

    test('round-trips', () => expectRoundTrip(settings, PushSettings.fromJson));

    // the body `GET /push/settings` answers in api/test/routes/push_test.dart
    test('reads the body the API sends', () {
      final read = PushSettings.fromJson({
        'topics': [
          {
            'topic': 'coaching.workout_digest',
            'group': 'coaching',
            'name': 'Workouts',
            'description': 'A daily round-up',
            'delivery': 'daily',
            'options': ['daily', 'off'],
          },
        ],
        'forPeople': [
          {'topic': 'coaching.workout_digest', 'connectionId': 'c', 'delivery': 'off'},
          {'topic': 'coaching.message', 'connectionId': null, 'delivery': 'off'},
        ],
      });
      expect(read.topics.single.options, ['daily', 'off']);
      expect(read.forPeople, [
        (topic: 'coaching.workout_digest', connectionId: 'c', delivery: 'off'),
        (topic: 'coaching.message', connectionId: null, delivery: 'off'),
      ]);
    });

    test('a delivery word this build has never heard of is carried', () {
      final read = PushSettings.fromJson({
        'topics': [
          {
            ...settings.topics.single.toMap(),
            'delivery': 'weekly',
            'options': ['weekly', 'off'],
          },
        ],
      });
      expect(read.topics.single.delivery, 'weekly');
      expect(read.forPeople, isEmpty);
    });

    test('a topic it cannot read leaves the rest', () {
      final read = PushSettings.fromJson({
        'topics': [
          {'topic': 'coaching.message', 'options': 3},
          settings.topics.single.toMap(),
        ],
      });
      expect(read.topics.single.topic, 'coaching.message');
    });
  });

  group('keys', () {
    final row = {
      'id': 'd1',
      'user_id': 'u1',
      'identity_key': 'i',
      'signing_key': 's',
      'fallback_key': 'f',
      'signature': 'sig',
      'vouched_by': 'd0',
      'created_at': at,
      'key_id': 'k1',
      'key': 'one-time',
    };

    test('CryptoDevices round-trips', () {
      expectRoundTrip(CryptoDevices([CryptoDevice.fromRow(row)]), CryptoDevices.fromJson);
    });

    test('CryptoDevices reads what a claim answers, from the rows the API reads', () {
      final read = CryptoDevices.fromJson(
        wire(
          CryptoDevices([
            CryptoDevice.fromRow(row),
            CryptoDevice.fromRow({
              ...row,
              'id': 'd2',
              'signature': null,
              'vouched_by': null,
              'key_id': null,
              'key': null,
            }),
          ]),
        ),
      );
      expect(read.devices.map((device) => device.id), ['d1', 'd2']);
      expect(read.devices.first.oneTimeKey, 'one-time');
      expect(read.devices.last.oneTimeKey, isNull);
      expect(read.devices.first.createdAt, at);
    });

    final item = QueuedItem.fromRow({
      'id': 'q1',
      'recipient_device_id': 'd1',
      'sender_device_id': 'd2',
      'kind': 'key',
      'content': 'sealed',
      'created_at': at,
    });

    test('QueuedItems round-trips', () => expectRoundTrip(QueuedItems([item]), QueuedItems.fromJson));

    test('QueuedItems reads the queue the API sends, a kind it does not know too', () {
      final read = QueuedItems.fromJson({
        'items': [
          {
            'id': 'q1',
            'recipientDeviceId': 'd1',
            'kind': 'something_new',
            'content': 'sealed',
            'createdAt': '2026-11-01T09:30:00.000Z',
          },
        ],
      });
      expect(read.items.single.kind, 'something_new');
      expect(read.items.single.senderDeviceId, isNull);
      expect(read.items.single.createdAt, at);
    });

    test('OneTimeKeyCount round-trips', () => expectRoundTrip(const OneTimeKeyCount(12), OneTimeKeyCount.fromJson));

    test('OneTimeKeyCount reads the API body', () => expect(OneTimeKeyCount.fromJson({'count': 0}).count, 0));
  });

  group('threads', () {
    final row = {
      'id': 't1',
      'connection_id': connection,
      'other_id': 'u2',
      'other_name': 'Alex',
      'other_avatar': 'https://cdn/a.png',
      'unread': 3,
      'last_at': at,
      'cleared_at': later,
      'cleared_by': 'u2',
    };

    test('Thread round-trips', () => expectRoundTrip(Thread.fromRow(row), Thread.fromJson));

    test('ThreadList round-trips, with the unread it adds up', () {
      final list = ThreadList([
        Thread.fromRow(row),
        Thread.fromRow({'id': 't2', 'unread': 2}),
      ]);
      expectRoundTrip(list, ThreadList.fromJson);
      expect(wire(list)['unread'], 5);
    });

    test('ThreadList reads an inbox as the API sends it, someone gone too', () {
      final read = ThreadList.fromJson(
        wire(
          ThreadList([
            Thread.fromRow(row),
            Thread.fromRow({'id': 't2', 'connection_id': null, 'other_id': null, 'unread': null}),
          ]),
        ),
      );
      expect(read.threads.first.lastAt, at);
      expect(read.threads.first.clearedAt, later);
      expect(read.threads.last.otherId, isNull);
      expect(read.threads.last.unread, 0);
    });

    final note = CoachNote.fromRow({'id': 'n1', 'connection_id': connection, 'content': 'sealed', 'updated_at': at});

    test('CoachNote round-trips', () => expectRoundTrip(note, CoachNote.fromJson));

    test('CoachNote reads a page of notes as the API sends it', () {
      final page = {
        'notes': [
          wire(note),
          wire(CoachNote.fromRow({'id': 'n2', 'content': 'x', 'updated_at': later})),
        ],
        'cursor': 'n2',
      };
      final read = readEach(page['notes']! as List, CoachNote.fromJson);
      expect(read.items.map((note) => note.id), ['n1', 'n2']);
      expect(read.items.first.connectionId, connection);
      expect(read.items.last.connectionId, isNull);
      expect(read.unread, isEmpty);
    });
  });

  group('coach library', () {
    final row = {
      'id': program,
      'name': 'Plan',
      'version': 2,
      'body': {
        'name': 'Plan',
        'sessions': [
          {'name': 'Day', 'exercises': <Object?>[]},
        ],
      },
      'updated_at': at,
    };

    test('CoachProgram round-trips, with a body and without', () {
      expectRoundTrip(CoachProgram.fromRow(row), CoachProgram.fromJson);
      expectRoundTrip(CoachProgram.fromRow({...row, 'body': null}), CoachProgram.fromJson);
    });

    test('CoachProgram reads one program as the API sends it', () {
      final read = CoachProgram.fromJson(wire(CoachProgram.fromRow(row)));
      expect(read.version, 2);
      expect(read.body?['sessions'], hasLength(1));
      expect(read.updatedAt, at);
    });

    final holder = CoachProgramHolder.fromRow({
      'connection_id': connection,
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': null,
      'program_id': program,
      'library_version': 1,
    });

    test('CoachProgramHolder round-trips', () => expectRoundTrip(holder, CoachProgramHolder.fromJson));

    test('CoachProgramHolders round-trips and reads as the API sends it', () {
      expectRoundTrip(CoachProgramHolders([holder]), CoachProgramHolders.fromJson);
      final read = CoachProgramHolders.fromJson(wire(CoachProgramHolders([holder])));
      expect(read.holders.single.studentName, 'Sam');
      expect(read.holders.single.studentAvatar, isNull);
      expect(read.holders.single.version, 1);
    });

    test('ProgramDelivery round-trips', () {
      expectRoundTrip(
        const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
        ProgramDelivery.fromJson,
      );
      expectRoundTrip(
        const ProgramDelivery(connectionId: connection, delivered: false, reason: 'program_limit'),
        ProgramDelivery.fromJson,
      );
    });

    // the deliveries `POST /library-programs/:id/send` answers in
    // api/test/routes/coach_library_test.dart: one refused, one arrived
    test('ProgramDeliveries reads a send as the API answers it', () {
      final deliveries = const ProgramDeliveries([
        ProgramDelivery(connectionId: connection, delivered: false, reason: 'not_coaching'),
        ProgramDelivery(connectionId: session, delivered: true, programId: program),
      ]);
      expectRoundTrip(deliveries, ProgramDeliveries.fromJson);
      final read = ProgramDeliveries.fromJson(wire(deliveries));
      expect(read.deliveries.first.delivered, isFalse);
      expect(read.deliveries.first.reason, 'not_coaching');
      expect(read.deliveries.last.programId, program);
    });
  });

  group('program changes', () {
    final row = {
      'id': 'ch1',
      'program_id': program,
      'session_id': session,
      'actor_id': 'coach',
      'kind': 'edit',
      'revision': 4,
      'before': {'name': 'Day'},
      'after': {'name': 'Day 1'},
      'stale': true,
      'at': at,
    };

    test('ProgramChange round-trips, stale and not', () {
      expectRoundTrip(ProgramChange.fromRow(row, cursor: 'c1'), ProgramChange.fromJson);
      expectRoundTrip(
        ProgramChange.fromRow({...row, 'session_id': null, 'before': null, 'stale': false}),
        ProgramChange.fromJson,
      );
    });

    test('ProgramChanges reads what changed as the API sends it, a kind it does not know too', () {
      final changes = ProgramChanges([
        ProgramChange.fromRow(row, cursor: 'c1'),
        ProgramChange.fromRow({...row, 'id': 'ch2', 'kind': 'merge', 'stale': null}, cursor: 'c2'),
      ]);
      expectRoundTrip(changes, ProgramChanges.fromJson);
      final read = ProgramChanges.fromJson(wire(changes));
      expect(read.changes.first.stale, isTrue);
      expect(read.changes.first.after, {'name': 'Day 1'});
      expect(read.changes.last.kind, 'merge');
      expect(read.changes.last.stale, isFalse);
      expect(read.changes.last.cursor, 'c2');
    });

    test('WorkoutPlan round-trips and reads the API body', () {
      final plan = const WorkoutPlan({
        'templateId': session,
        'exercises': [
          {'exercise': 'Squat', 'sets': 3},
        ],
      });
      expectRoundTrip(plan, WorkoutPlan.fromJson);
      expect(WorkoutPlan.fromJson(wire(plan)).plan['templateId'], session);
    });

    // what `getCopy` builds: a coach's copy, its sessions, and its position folded
    // as the route folds it
    final copy = Program(
      id: program,
      name: 'Plan',
      sessions: [session],
      perWeek: 3,
      weeks: 4,
      coachId: 'coach',
      coachName: 'Coach',
      revision: 2,
      sessionRevisions: {session: 1},
    );
    final view = CoachProgramView(
      program: copy,
      sessions: [
        Template.fromJson(const {'id': session, 'name': 'Day', 'order': 0, 'programId': program}),
      ],
      position: ProgramPosition.of(copy, marks: const [], actions: const [], now: later).toMap(),
    );

    test('CoachProgramView round-trips', () => expectRoundTrip(view, CoachProgramView.fromJson));

    test('CoachProgramView reads a copy as the API sends it', () {
      final read = CoachProgramView.fromJson(wire(view));
      expect(read.program.coachId, 'coach');
      expect(read.program.revision, 2);
      expect(read.program.sessionRevisions, {session: 1});
      expect(read.sessions.single.id, session);
      expect(read.position['week'], 1);
      expect(read.position['next'], session);
    });
  });

  group('roster', () {
    final row = {
      'connection_id': connection,
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': 'https://cdn/s.png',
      'status': 'active',
      'accepted_at': at,
      'program_id': program,
      'program_name': 'Plan',
      'program_week': 2,
      'program_weeks': 8,
      'recent': [at, later],
      'last_trained_at': later,
      'reasons': ['lighter', 'gap'],
    };

    test('ClientSummary round-trips', () {
      expectRoundTrip(ClientSummary.fromRow(row), ClientSummary.fromJson);
      expectRoundTrip(
        ClientSummary(connectionId: connection, studentId: 's2', status: 'active'),
        ClientSummary.fromJson,
      );
    });

    test('ClientSummary reads a roster page as the API sends it, a reason it does not know too', () {
      final page = {
        'clients': [
          wire(
            ClientSummary.fromRow({
              ...row,
              'reasons': ['lighter', 'something_new'],
            }),
          ),
          // `GET /coach/clients` in api/test/routes/roster_test.dart
          wire(ClientSummary(connectionId: session, studentId: 's2', status: 'active')),
        ],
      };
      final read = readEach(page['clients']!, ClientSummary.fromJson);
      expect(read.unread, isEmpty);
      expect(read.items.first.recent, [at, later]);
      expect(read.items.first.reasons, ['lighter', 'something_new']);
      expect(read.items.first.programWeek, 2);
      expect(read.items.last.acceptedAt, isNull);
      expect(read.items.last.recent, isEmpty);
    });

    final item = CoachFeedItem.fromRow({
      'kind': 'workout',
      'id': 'w1',
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': null,
      'at': at,
      'title': 'Push day',
    }, cursor: 'opaque');

    test('CoachFeedItem round-trips', () => expectRoundTrip(item, CoachFeedItem.fromJson));

    test('CoachFeedItem reads a feed page as the API sends it, a kind it does not know too', () {
      final page = {
        'items': [
          wire(item),
          {...wire(item), 'kind': 'milestone', 'id': 'x'},
        ],
        'cursor': 'opaque',
      };
      final read = readEach(page['items']! as List, CoachFeedItem.fromJson);
      expect(read.items.map((item) => item.kind), ['workout', 'milestone']);
      expect(read.items.first.at, at);
      // the page's cursor is the one to pass back; the items carry none
      expect(read.items.first.cursor, isNull);
    });
  });

  group('invitations', () {
    final accepted = Connection.fromRow({
      'target_id': 'coach',
      'role': 'COACH',
      'domain': 'fitness',
      'status': 'active',
      'created_at': at,
      'connection_id': connection,
      'accepted_at': later,
      'shares': ['history'],
    });

    test('Connection round-trips, as a list too', () {
      expectRoundTrip(accepted, Connection.fromJson);
      expectRoundTrip(ConnectionListResponse([accepted]), ConnectionListResponse.fromJson);
    });

    test('Connection reads the API body, a share it does not know too', () {
      final read = Connection.fromJson({
        ...wire(accepted),
        'shares': ['history', 'something_new'],
      });
      expect(read.id, 'coach|COACH|FITNESS');
      expect(
        (read.role, read.domain, read.status),
        (ConnectionRole.coach, ConnectionDomain.fitness, ConnectionStatus.active),
      );
      expect(read.acceptedAt, later);
      expect(read.shares, ['history', 'something_new']);
    });

    test('a connection in a status this build does not know leaves the rest of the list', () {
      final read = ConnectionListResponse.fromJson({
        'connections': [
          {...wire(accepted), 'status': 'something_new'},
          wire(accepted),
        ],
      });
      expect(read.connections, hasLength(1));
    });

    test('AcceptedInvitation round-trips, with a program and without', () {
      expectRoundTrip(AcceptedInvitation(accepted), AcceptedInvitation.fromJson);
      expectRoundTrip(
        AcceptedInvitation(
          accepted,
          delivery: const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
        ),
        AcceptedInvitation.fromJson,
      );
    });

    // `POST /invitations/:token/accept`: the connection, and how the program went
    test('AcceptedInvitation reads what accepting answers', () {
      final none = AcceptedInvitation.fromJson(wire(AcceptedInvitation(accepted)));
      expect(none.connection.connectionId, connection);
      expect(none.delivery, isNull);

      final arrived = AcceptedInvitation.fromJson(
        wire(
          AcceptedInvitation(
            accepted,
            delivery: const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
          ),
        ),
      );
      expect(arrived.delivery?.delivered, isTrue);
      expect(arrived.delivery?.programId, program);
      expect(arrived.delivery?.connectionId, connection);

      final refused = AcceptedInvitation.fromJson(
        wire(
          AcceptedInvitation(
            accepted,
            delivery: const ProgramDelivery(connectionId: connection, delivered: false, reason: 'program_limit'),
          ),
        ),
      );
      expect(refused.delivery?.delivered, isFalse);
      expect(refused.delivery?.programId, isNull);
    });

    final blocked = BlockedPerson.fromRow({
      'blocked_id': 'u9',
      'username': 'Pat',
      'avatar_url': null,
      'created_at': at,
    });

    test('BlockedPerson round-trips', () => expectRoundTrip(blocked, BlockedPerson.fromJson));

    test('BlockedPerson reads a page of blocks as the API sends it', () {
      final read = readEach([wire(blocked)], BlockedPerson.fromJson);
      expect(read.items.single.id, 'u9');
      expect(read.items.single.name, 'Pat');
      expect(read.items.single.avatar, isNull);
      expect(read.items.single.since, at);
    });
  });

  group('Workout.copy (review 380-18)', () {
    final workout = Workout.fromJson({...Workout().toMap(), 'loggedBy': 'coach', 'loggedByName': 'Coach'});

    test('the same session keeps who logged it', () {
      final same = workout.copy(sameId: true);
      expect((same.loggedBy, same.loggedByName), ('coach', 'Coach'));
      expect(same.toMap(), allOf(containsPair('loggedBy', 'coach'), containsPair('loggedByName', 'Coach')));
    });

    test('a repeat is the owner\'s own', () {
      final repeat = workout.copy();
      expect((repeat.loggedBy, repeat.loggedByName), (null, null));
    });
  });
}
