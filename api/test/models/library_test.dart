import 'dart:convert';
import 'dart:io';

import 'package:heart/models/library.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// Two programs of the rendered `static/programs`, cut down by hand to them,
/// the sources they cite and the safety notes they show.
const _fixture = 'test/fixtures/programs/library.json';

const _walking = '01900000-0000-7000-8000-0000000000e1';
const _stand = '01900000-0000-7000-8000-0000000000e2';

Map<String, dynamic> _content() => jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;

LibraryView _view([String locale = 'en', Map<String, dynamic>? content]) {
  return LibraryView(
    content ?? _content(),
    locale: locale,
    exercises: {
      'walking': (id: _walking, name: locale == 'es' ? 'Caminar' : 'Walking'),
      'single-leg-stand': (id: _stand, name: 'Single Leg Stand'),
    },
  );
}

void main() {
  group('LibraryView (heart-api#259)', () {
    test('the list has what helps choose, in the caller\'s language', () {
      final list = _view().list();
      expect(list.map((program) => program['key']), ['walk_and_move', 'full_body_three']);
      expect(list.first, {
        'key': 'walk_and_move',
        'name': 'Walk and move',
        'note': startsWith('Three walks a week'),
        'audience': 'getting_back',
        'equipment': 'none',
        'perWeek': 3,
        'minutes': isA<int>(),
        'weeks': isA<int>(),
        'who': startsWith('For starting from very little'),
      });
      final spanish = _view('es').list().first;
      expect(spanish['name'], 'Camina y muévete');
      expect(spanish['who'], startsWith('Para empezar'));
      expect(_view('es_MX').list().first['name'], 'Camina y muévete', reason: 'a regional locale takes its language');
      expect(_view('de').list().first['name'], 'Walk and move', reason: 'English where untranslated');
    });

    test('one program in full: copy, sessions by name, research with its sources, safety, next', () {
      final program = _view().program('walk_and_move')!;
      expect(program['grows'], startsWith('Each walk gets five minutes longer'));
      final sessions = (program['sessions'] as List).cast<Map>();
      expect(sessions.map((session) => session['name']), ['Walk and strengthen', 'Walk and balance', 'Walk']);
      final walk = (sessions.first['exercises'] as List).first as Map;
      expect(walk['exercise'], 'walking');
      expect(walk['name'], 'Walking');
      expect((program['exercises'] as Map)['walking'], 'Walking');
      expect(
        (program['exercises'] as Map)['sit-to-stand'],
        'sit-to-stand',
        reason: 'a key the caller\'s library lacks reads as itself',
      );

      final research = (program['research'] as List).cast<Map>();
      expect(research.first['sources'], ['who_2020']);
      expect(research.first['about'], [
        {'on': 'program'},
        {'on': 'grows'},
      ]);
      expect(research.last['about'], [
        {'on': 'week'},
        {'on': 'session', 'session': 'Walk and strengthen'},
        {'on': 'session', 'session': 'Walk and balance'},
      ], reason: 'a session anchor names the session');
      final source = (program['sources'] as Map)['who_2020'] as Map;
      expect(source.keys, containsAll(['title', 'who', 'year', 'url', 'finding']));
      expect(source['finding'], isA<String>());
      expect(program['safety'], isNotEmpty);
      expect(program['next'], isEmpty, reason: 'first_steps is not in this cut of the file');
    });

    test('next names a program the file has; an unknown key is null', () {
      final content = _content();
      final programs = (content['programs'] as List).cast<Map<String, dynamic>>();
      programs.first['next'] = ['full_body_three', 'nowhere'];
      expect(_view('en', content).program('walk_and_move')!['next'], [
        {'key': 'full_body_three', 'name': 'Full body, three days'},
      ]);
      expect(_view().program('nowhere'), isNull);
    });

    test('an occurrence\'s own rule sits on it, and a share of one names its session (heart-api#255)', () {
      final content = _content();
      final program = (content['programs'] as List).cast<Map<String, dynamic>>().first;
      final [first, second, ...] = (program['sessions'] as List).cast<Map>();
      final heavy = (first['exercises'] as List).first as Map;
      final light = (second['exercises'] as List).first as Map;
      program['rules'] = {
        ...program['rules'] as Map,
        heavy['id']: {'kind': 'addWeight', 'step': 2.5},
      };
      ((light['sets'] as List).first as Map)['target'] = {
        'reps': {'min': 5, 'max': 5},
        'share': 0.9,
        'of': 'walking',
        'ofSlot': heavy['id'],
      };
      final view = _view('en', content).program('walk_and_move')!;
      expect((view['rules'] as Map).keys, isNot(contains(heavy['id'])));
      expect((view['exercises'] as Map).keys, isNot(contains(heavy['id'])));
      final sessions = (view['sessions'] as List).cast<Map>();
      expect(((sessions.first['exercises'] as List).first as Map)['rule'], {'kind': 'addWeight', 'step': 2.5});
      final target = ((((sessions[1]['exercises'] as List).first as Map)['sets'] as List).first as Map)['target'];
      expect(target, containsPair('ofSlot', 'Walk and strengthen'));
    });

    group('research for a copy', () {
      Template session(String id, List<(String, String)> exercises) {
        return Template.fromJson({
          'id': id,
          'order': 0,
          'name': id,
          'exercises': [
            for (final (slot, exercise) in exercises)
              {
                'id': slot,
                'exercise': {'id': exercise, 'name': exercise, 'category': 'Duration', 'target': 'Legs'},
                'sets': [],
              },
          ],
        });
      }

      final copy = Program(
        name: 'Walk and move',
        source: 'walk_and_move',
        sessions: const ['s1', 's2', 's3'],
      );
      final sessions = [
        session('s1', [('t1', _walking), ('t2', '01900000-0000-7000-8000-0000000000e3')]),
        session('s2', [('t3', _walking), ('t4', _stand)]),
        session('s3', [('t5', _walking)]),
      ];

      test('anchors move to the copy: a rule by exercise id, a session by its place', () {
        final research = _view().researchFor(copy, sessions)!;
        expect(research['key'], 'walk_and_move');
        final claims = (research['claims'] as List).cast<Map>();
        expect(claims[1]['about'], [
          {'on': 'grows'},
          {'on': 'rule', 'exercise': _walking},
        ]);
        expect(claims[2]['about'], [
          {'on': 'week'},
          {'on': 'session', 'session': 's1'},
          {'on': 'session', 'session': 's2'},
        ]);
        expect((research['sources'] as Map).keys, containsAll(['who_2020', 'walk_with_ease', 'otago_2022']));
      });

      test('an exercise anchor holds only on the same exercise at the same place', () {
        final content = _content();
        final library = (content['programs'] as List).cast<Map<String, dynamic>>().first;
        final second = (library['sessions'] as List)[1] as Map;
        final stand = ((second['exercises'] as List)[1] as Map)['id'];
        final walk = ((second['exercises'] as List)[0] as Map)['id'];
        ((library['why'] as List).first as Map)['about'] = [
          {'on': 'exercise', 'session': second['id'], 'exercise': stand},
          {'on': 'exercise', 'session': second['id'], 'exercise': walk},
        ];
        final moved = [
          sessions[0],
          session('s2', [('t3', _stand), ('t4', _stand)]),
          sessions[2],
        ];

        final kept = _view('en', content).researchFor(copy, sessions)!;
        expect(((kept['claims'] as List).first as Map)['about'], [
          {'on': 'exercise', 'session': 's2', 'exercise': 't4'},
          {'on': 'exercise', 'session': 's2', 'exercise': 't3'},
        ]);
        final changed = _view('en', content).researchFor(copy, moved)!;
        expect(((changed['claims'] as List).first as Map)['about'], [
          {'on': 'exercise', 'session': 's2', 'exercise': 't4'},
        ], reason: 'the walk was swapped out of its place');
      });

      test('a claim whose parts are all gone sits on the program; no source is no research', () {
        final short = Program(name: 'Mine', source: 'walk_and_move', sessions: const ['s1']);
        final claims = (_view().researchFor(short, [sessions.first])!['claims'] as List).cast<Map>();
        expect(claims[2]['about'], [
          {'on': 'week'},
          {'on': 'session', 'session': 's1'},
        ]);
        final gone = _content();
        ((gone['programs'] as List).first as Map)['why'] = [
          {
            'text': {'en': 'x'},
            'sources': ['who_2020'],
            'about': [
              {'on': 'session', 'session': 'not-a-session'},
            ],
          },
        ];
        expect(((_view('en', gone).researchFor(short, [sessions.first])!['claims'] as List).single as Map)['about'], [
          {'on': 'program'},
        ]);
        expect(_view().researchFor(Program(name: 'Own', sessions: const []), const []), isNull);
        expect(_view().researchFor(Program(name: 'Old', source: 'retired', sessions: const []), const []), isNull);
      });
    });
  });
}
