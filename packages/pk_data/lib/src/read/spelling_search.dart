import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

/// The SQL of a search that forgives spelling (M56), for items and parties.
///
/// `name_search` holds `plain|key~SKELETON` ([nameSearchColumn]). A row
/// matches when what was typed is in its plain name, or when every word
/// typed is in its key — or, for a word long enough to trust it, in its
/// skeleton. The matches are then ranked, so the spelling the shopkeeper
/// typed comes before the spellings that only sound like it:
///
/// | rank | what matched                                              |
/// |------|-----------------------------------------------------------|
/// | 0    | the whole name, or the code or barcode                    |
/// | 1    | the start of the name, or the phone                       |
/// | 2    | the start of a word in the name                           |
/// | 3    | every word, spelling forgiven, in any order; or as typed  |
/// | 4    | every word, by its consonants only (see [SpellingWord])   |
///
/// Substrings are found with `instr`, not `LIKE '%…%'`: on a row that does
/// not match — nearly every row, on every keystroke — `instr` is a plain
/// scan where `LIKE` folds the case of every character it passes. `instr`
/// is case-sensitive, which is what keeps a key (lower case) and a skeleton
/// (capitals) from ever being found in each other. Nothing needs escaping:
/// the parts are letters, digits and spaces, and the only `LIKE` patterns
/// are prefixes.
///
/// A ranked search cannot stop at the fortieth match the way an unranked
/// one could, so it reads the whole catalogue on every keystroke. The cost
/// on twenty thousand items is printed by `catalogue_performance_test`,
/// and is why everything here is kept to as few comparisons a row as it
/// can be.
final class SpellingSearch {
  SpellingSearch(
    this.query, {
    required this.column,
    this.exactColumns = const [],
    this.containsColumns = const [],
  }) : _words = query.words.every((w) => w.key.length < 2)
           // A key of one letter is not a spelling of anything: "qqqq" is
           // "k", which is in half the catalogue. What was typed is still
           // looked for as typed.
           ? const []
           : query.words;

  final SpellingQuery query;

  /// The `name_search` column, qualified: `i.name_search`.
  final String column;

  /// Columns matched against exactly what was typed: a code, a barcode.
  final List<String> exactColumns;

  /// Columns that match when they contain what was typed: a phone number.
  final List<String> containsColumns;

  final List<SpellingWord> _words;

  String get _has => 'instr($column, ?) > 0';

  /// Whether the as-typed test would only repeat the word's own: a single
  /// word whose key is what was typed ("dal", "sufi"). Both halves of the
  /// column are lower case, so one `instr` covers them both.
  bool get _plainIsTheKey =>
      _words.length == 1 && _words.single.key == query.plain;

  /// A boolean SQL expression: this row matches.
  String get where {
    final parts = <String>[
      for (final c in exactColumns) '$c = ?',
      for (final c in containsColumns) '$c LIKE ?',
      if (query.plain.isNotEmpty && !_plainIsTheKey) _has,
      if (_words.isNotEmpty)
        '(${[for (final w in _words) w.skeleton == null ? _has : '($_has OR $_has)'].join(' AND ')})',
    ];
    return parts.isEmpty ? '0' : '(${parts.join(' OR ')})';
  }

  /// The values for [where]'s placeholders, in order.
  List<Variable<Object>> get whereVariables => [
    for (final _ in exactColumns) Variable<String>(query.raw),
    for (final _ in containsColumns) Variable<String>('%${query.raw}%'),
    if (query.plain.isNotEmpty && !_plainIsTheKey)
      Variable<String>(query.plain),
    for (final w in _words) ...[
      Variable<String>(w.key),
      if (w.skeleton case final bones?) Variable<String>(bones.toUpperCase()),
    ],
  ];

  /// An integer SQL expression: how good a match this row is, 0 best. See
  /// the table above. Worked out only for rows [where] has let through.
  String get rank {
    final exact = [
      for (final c in exactColumns) '$c = ?',
      if (query.plain.isNotEmpty) '$column LIKE ?',
    ];
    final start = [
      for (final c in containsColumns) '$c LIKE ?',
      if (query.plain.isNotEmpty) '$column LIKE ?',
    ];
    final spelled = [
      if (query.plain.isNotEmpty) _has,
      if (_words.isNotEmpty)
        '(${[for (final _ in _words) _has].join(' AND ')})',
    ];
    final branches = [
      if (exact.isNotEmpty) 'WHEN ${exact.join(' OR ')} THEN 0',
      if (start.isNotEmpty) 'WHEN ${start.join(' OR ')} THEN 1',
      if (query.plain.isNotEmpty) 'WHEN $_has THEN 2',
      if (spelled.isNotEmpty) 'WHEN ${spelled.join(' OR ')} THEN 3',
    ];
    return branches.isEmpty ? '4' : '(CASE ${branches.join(' ')} ELSE 4 END)';
  }

  /// The values for [rank]'s placeholders, in order.
  List<Variable<Object>> get rankVariables => [
    for (final _ in exactColumns) Variable<String>(query.raw),
    if (query.plain.isNotEmpty)
      Variable<String>('${query.plain}$nameSearchSeparator%'),
    for (final _ in containsColumns) Variable<String>('%${query.raw}%'),
    if (query.plain.isNotEmpty) ...[
      Variable<String>('${query.plain}%'),
      Variable<String>(' ${query.plain}'),
      Variable<String>(query.plain),
    ],
    for (final w in _words) Variable<String>(w.key),
  ];
}
