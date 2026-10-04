import 'package:heart_models/heart_models.dart';
import 'package:heart_models/src/models/search.dart' show searchNormalized, withinOneEdit;
import 'package:test/test.dart';

Exercise _library(String key, String name, {List<String> aliases = const [], Map? muscles}) {
  return Exercise.fromJson({
    'id': '018f2c9a-0000-7000-8000-${key.hashCode.toRadixString(16).padLeft(12, '0')}',
    'key': key,
    'name': name,
    'category': 'Barbell',
    'target': 'Chest',
    'aliases': aliases,
    'muscles': ?muscles,
  });
}

final _glossary = SearchGlossary.fromJson({
  'db': {
    'words': ['dumbbell'],
  },
  'EZ': {
    'words': ['ez bar'],
  },
  'lats': {
    'muscles': ['latissimus_dorsi'],
  },
  'hams': {
    'muscles': ['hamstrings', 'biceps_femoris'],
  },
  'mancuernas': {
    'words': ['mancuerna'],
  },
});

void main() {
  final bench = _library('bench-press-barbell', 'Bench Press (Barbell)');
  final inclineDb = _library('incline-bench-press-dumbbell', 'Incline Bench Press (Dumbbell)');
  final ohp = _library('overhead-press-barbell', 'Overhead Press (Barbell)', aliases: ['ohp', 'military press']);
  final rdl = _library('romanian-deadlift-barbell', 'Romanian Deadlift (Barbell)', aliases: ['rdl']);
  final pulldown = _library(
    'lat-pulldown-cable',
    'Lat Pulldown (Cable)',
    muscles: {
      'primary': {
        'ids': ['latissimus_dorsi_l', 'latissimus_dorsi_r'],
      },
      'secondary': {
        'ids': ['biceps_brachii_caput_longum_l'],
      },
    },
  );
  final row = _library(
    'bent-over-row-barbell',
    'Bent Over Row (Barbell)',
    muscles: {
      'primary': {
        'groups': ['back'],
      },
      'secondary': {
        'ids': ['latissimus_dorsi_l'],
      },
    },
  );
  final legCurl = _library(
    'lying-leg-curl-machine',
    'Lying Leg Curl (Machine)',
    muscles: {
      'primary': {
        'groups': ['hamstrings'],
      },
    },
  );

  group('tiers', () {
    test('prefix: the name starts with the query', () {
      expect(bench.match('bench'), SearchMatch.prefix);
      expect(bench.match('Bench  Pr'), SearchMatch.prefix);
      expect(bench.match('bench press (barb'), SearchMatch.prefix);
    });

    test('words: every query word is in a name or slug word, any order', () {
      expect(bench.match('press bench'), SearchMatch.words);
      expect(bench.match('barb pre'), SearchMatch.words);
    });

    test('vocabulary: a word found only through an alias', () {
      expect(ohp.match('ohp'), SearchMatch.vocabulary);
      expect(ohp.match('military'), SearchMatch.vocabulary);
      expect(rdl.match('rdl'), SearchMatch.vocabulary);
    });

    test('vocabulary: a word found only through the glossary', () {
      expect(inclineDb.match('db incline press', glossary: _glossary), SearchMatch.vocabulary);
      expect(pulldown.match('lats', glossary: _glossary), SearchMatch.vocabulary);
    });

    test('typo: one edit on a word of four or more letters', () {
      expect(bench.match('benhc press'), SearchMatch.typo);
      expect(bench.match('bnch'), SearchMatch.typo);
      expect(bench.match('presss'), SearchMatch.typo);
    });

    test('the worst word decides the tier', () {
      expect(inclineDb.match('db incline', glossary: _glossary), SearchMatch.vocabulary);
      expect(inclineDb.match('db inclnie', glossary: _glossary), SearchMatch.typo);
    });

    test('tiers rank best first', () {
      final ranked = [SearchMatch.typo, SearchMatch.prefix, SearchMatch.vocabulary, SearchMatch.words]..sort();
      expect(ranked, [SearchMatch.prefix, SearchMatch.words, SearchMatch.vocabulary, SearchMatch.typo]);
    });
  });

  group('no match', () {
    test('a word that matches nothing fails the whole query', () {
      expect(bench.match('bench squat'), isNull);
      expect(ohp.match('ohp curl'), isNull);
    });

    test('short words never match by typo', () {
      expect(bench.match('bnc'), isNull);
    });

    test('two edits are not a typo', () {
      expect(bench.match('bnhc'), isNull);
    });

    test('glossary words need the glossary', () {
      expect(inclineDb.match('db'), isNull);
      expect(legCurl.match('hams'), isNull);
      // without it, `lats` is only a typo of the name's `lat`
      expect(pulldown.match('lats'), SearchMatch.typo);
    });

    test('glossary muscles match primary muscles only', () {
      expect(row.match('lats', glossary: _glossary), isNull);
    });

    test('a glossary word matches whole, not as a part', () {
      expect(pulldown.match('lat', glossary: _glossary), SearchMatch.prefix);
      expect(inclineDb.match('d', glossary: _glossary), SearchMatch.words);
    });
  });

  group('matching', () {
    test('an empty query matches everything', () {
      expect(bench.match(''), SearchMatch.prefix);
      expect(bench.match('   '), SearchMatch.prefix);
    });

    test('muscle groups and id prefixes both answer a muscle word', () {
      expect(legCurl.match('hams', glossary: _glossary), SearchMatch.vocabulary);
    });

    test('glossary words are normalized on both sides', () {
      expect(_library('curl-ez-bar', 'Curl (EZ-Bar)').match('ez', glossary: _glossary), SearchMatch.words);
      expect(_glossary['ez'], isNotNull);
    });

    test('accents and case fold', () {
      final jalon = _library('lat-pulldown-cable', 'Jalón al pecho (polea)');
      expect(jalon.match('JALON'), SearchMatch.prefix);
      expect(jalon.match('pecho jalon'), SearchMatch.words);
    });

    test('the English slug matches in every locale', () {
      final es = _library('bench-press-dumbbell', 'Press de banca con mancuernas', aliases: ['press plano']);
      expect(es.match('bench dumbbell'), SearchMatch.words);
      expect(es.match('db bench', glossary: _glossary), SearchMatch.vocabulary);
      expect(es.match('plano'), SearchMatch.vocabulary);
    });
  });

  group('Exercise.aliases', () {
    test('round-trips through fromJson and toMap', () {
      expect(ohp.aliases, ['ohp', 'military press']);
      expect(Exercise.fromJson(ohp.toMap()).aliases, ['ohp', 'military press']);
    });

    test('absent, empty or malformed reads as none, and none is not written', () {
      expect(bench.aliases, isEmpty);
      expect(bench.toMap().containsKey('aliases'), isFalse);
      final malformed = Exercise.fromJson({...bench.toMap(), 'aliases': 'ohp'});
      expect(malformed.aliases, isEmpty);
    });

    test('user-created exercises have none', () {
      final custom = Exercise(name: 'My Press', category: .barbell, target: .chest);
      expect(custom.aliases, isEmpty);
    });

    test('copyWith carries them', () {
      expect(ohp.copyWith(isArchived: true).aliases, ohp.aliases);
    });
  });

  group('SearchGlossary', () {
    test('parses the published form and round-trips', () {
      expect(_glossary['db']!.words, ['dumbbell']);
      expect(_glossary['lats']!.muscles, ['latissimus_dorsi']);
      expect(_glossary['nope'], isNull);
      final again = SearchGlossary.fromJson(_glossary.toMap());
      expect(again['hams']!.muscles, ['hamstrings', 'biceps_femoris']);
    });

    test('skips malformed entries instead of failing', () {
      final glossary = SearchGlossary.fromJson({
        'db': 'dumbbell',
        'bb': {
          'words': ['barbell', 3],
        },
      });
      expect(glossary['db'], isNull);
      expect(glossary['bb']!.words, ['barbell']);
    });

    test('empty', () {
      expect(SearchGlossary.empty().isEmpty, isTrue);
      expect(bench.match('db', glossary: SearchGlossary.empty()), isNull);
    });
  });

  group('helpers', () {
    test('searchNormalized folds case, accents and symbols', () {
      expect(searchNormalized('Développé-Couché (Haltères)'), 'developpecouche halteres');
      expect(searchNormalized('Жим лёжа'), 'жим лежа');
    });

    test('withinOneEdit', () {
      expect(withinOneEdit('bench', 'bench'), isTrue);
      expect(withinOneEdit('benhc', 'bench'), isTrue); // swap
      expect(withinOneEdit('bemch', 'bench'), isTrue); // substitution
      expect(withinOneEdit('bnch', 'bench'), isTrue); // deletion
      expect(withinOneEdit('bennch', 'bench'), isTrue); // insertion
      expect(withinOneEdit('bnehc', 'bench'), isFalse);
      expect(withinOneEdit('ben', 'bench'), isFalse);
      expect(withinOneEdit('hcneb', 'bench'), isFalse);
    });
  });
}
