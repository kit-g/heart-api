import 'misc.dart';

/// How a query matched an exercise, best first: sorting by [index] (or
/// [compareTo]) ranks results. "No match" is the absence of a value, never a
/// tier.
enum SearchMatch implements Comparable<SearchMatch> {
  /// The name starts with the query.
  prefix,

  /// Every query word is found in a name or slug word, in any order.
  words,

  /// At least one query word is found only through an alias or the glossary.
  vocabulary,

  /// At least one query word is found only with a single typo.
  typo;

  @override
  int compareTo(SearchMatch other) => index - other.index;
}

/// One glossary word: the words it stands for and the muscles it names.
abstract interface class SearchTerm implements Model {
  /// Phrases the word stands for (`db` → `dumbbell`, `ez` → `ez bar`),
  /// normalized; a phrase matches when every one of its words does.
  Iterable<String> get words;

  /// Muscles the word names (`lats`): a muscle id prefix
  /// (`latissimus_dorsi`) or a muscle group (`hamstrings`), matched against
  /// an exercise's primary muscles.
  Iterable<String> get muscles;
}

/// A locale's search vocabulary: words a lifter types that stand for other
/// words across the whole library — abbreviations and gym muscle names.
///
/// Published with the library, one per locale; keys are normalized on parse,
/// so lookups take a normalized query word.
abstract interface class SearchGlossary implements Model {
  /// What [word] (normalized) stands for, or null when the glossary has no
  /// such word.
  SearchTerm? operator [](String word);

  bool get isEmpty;

  /// The published form: `{"db": {"words": ["dumbbell"]}, "lats":
  /// {"muscles": ["latissimus_dorsi"]}}`. Malformed entries are skipped
  /// rather than failing the library read: search is a convenience.
  factory fromJson(Map json) = _SearchGlossary.fromJson;

  factory empty() => const _SearchGlossary({});
}

class _SearchTerm implements SearchTerm {
  @override
  final List<String> words;
  @override
  final List<String> muscles;

  const new({required this.words, required this.muscles});

  @override
  Map<String, dynamic> toMap() {
    return {
      if (words.isNotEmpty) 'words': words,
      if (muscles.isNotEmpty) 'muscles': muscles,
    };
  }
}

class _SearchGlossary implements SearchGlossary {
  final Map<String, SearchTerm> _terms;

  const new(this._terms);

  factory fromJson(Map json) {
    List<String> strings(Object? value) {
      return switch (value) {
        List l => [...l.whereType<String>()],
        _ => [],
      };
    }

    return _SearchGlossary({
      for (final MapEntry(:key, :value) in json.entries)
        if ((key, value) case (String word, Map entry))
          searchNormalized(word): _SearchTerm(
            words: [...strings(entry['words']).map(searchNormalized)],
            muscles: strings(entry['muscles']),
          ),
    });
  }

  @override
  SearchTerm? operator [](String word) => _terms[word];

  @override
  bool get isEmpty => _terms.isEmpty;

  @override
  Map<String, dynamic> toMap() {
    return {
      for (final MapEntry(:key, :value) in _terms.entries) key: value.toMap(),
    };
  }
}

/// Lower-cased, accents folded, symbols other than letters, digits and spaces
/// dropped: the one form every side of a search comparison is put in.
String searchNormalized(String s) {
  final lower = s.toLowerCase();
  final folded = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    folded.write(_folds[char] ?? char);
  }
  return folded.toString().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '');
}

/// Single-character accent folds for the library's scripts (Latin, Cyrillic).
const _folds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'œ': 'oe', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss', //
  'ё': 'е', //
};

/// True when [a] and [b] are at most one edit apart: an insertion, a
/// deletion, a substitution, or a swap of two adjacent characters
/// (restricted Damerau–Levenshtein ≤ 1).
bool withinOneEdit(String a, String b) {
  if (a == b) return true;
  final (short, long) = a.length <= b.length ? (a, b) : (b, a);
  if (long.length - short.length > 1) return false;

  var i = 0;
  while (i < short.length && short[i] == long[i]) {
    i++;
  }
  if (short.length == long.length) {
    // one substitution, or one adjacent swap
    final substituted = short.substring(i + 1) == long.substring(i + 1);
    final swapped =
        i + 1 < short.length &&
        short[i] == long[i + 1] &&
        short[i + 1] == long[i] &&
        short.substring(i + 2) == long.substring(i + 2);
    return substituted || swapped;
  }
  // one insertion into the shorter word
  return short.substring(i) == long.substring(i + 1);
}
