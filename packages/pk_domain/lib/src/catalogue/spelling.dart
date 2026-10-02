/// Search that forgives spelling (M56).
///
/// Nobody in a Pakistani shop spells an item the same way twice. Flour is
/// atta, aata and آٹا; sugar is cheeni and chini; cumin is zeera and jeera;
/// milk is doodh and dudh. Roman Urdu has no dictionary, the catalogue was
/// typed by whoever was on the counter the day the stock came in, and the
/// customer at the counter says the word, not its spelling. A search that
/// only matches letters for letters tells the cashier the shop has no sugar
/// while forty kilos of it sit behind them under "Cheeni".
///
/// So every name is kept in `name_search` as it was typed (lowercased,
/// punctuation set aside) and again as a SPELLING KEY: what it sounds like,
/// with the variations Roman Urdu actually has folded together. A search
/// builds the same key from what was typed and compares keys. The function
/// is deterministic and the same one writes the column and reads the query,
/// so a name always finds itself.
///
/// The key, word by word, in this order:
///
///  1. Urdu script is read into Roman letters first ([urduToRoman]), so
///     آٹا is "ata" and چینی is "chini" before anything else happens.
///  2. Only letters and digits count. A dot, hyphen or apostrophe inside a
///     word is dropped, so "t.v." is "tv" and "7-up" is "7up"; the words of
///     a name are then run together, so "7 up" is "7up" too.
///  3. "ee" is one long i — cheeni, chini.
///  4. Any letter twice is once: aata/atta, doodh/dudh, achha/acha. Long
///     vowels are a doubled letter in Roman Urdu, so this is also aa/a,
///     oo/u and ii/i.
///  5. "eh" is "ah" — Rehman, Rahman; Mehmood, Mahmood.
///  6. "ae" is "ai" — chae, chai.
///  7. q is k, and a c that is not "ch" is k — qeema/keema, cola/kola.
///  8. v is w — Javed/Jawed, sevaiyan/sewaiyan.
///  9. An h after a consonant goes — chini/cini, ghee/gee, dhal/dal,
///     doodh/dood, shampoo/sampoo — and so does an h ending a word after a
///     vowel: subah/suba, Allah/Alla.
/// 10. z is j — zeera/jeera, Zubair/Jubair.
/// 11. o is u — roti/ruti, gosht/gusht, Usman/Osman, moong/mung.
/// 12. y is i — chay/chai, Riaz/Riyaz, biryani/biriyani; a word ending
///     "ie" ends "i" — chaye/chai, cookie/cooki.
/// 13. Doubles are folded once more, because the steps above make new ones.
///
/// What it deliberately keeps apart, because the shop sells both: a single
/// e is not an i, so tel (oil) is not til (sesame); a is not i, so chini is
/// not chana and dal is not dil. Digits are never folded: a 100 g packet is
/// not a 10 g one.
///
/// Urdu script writes long vowels and leaves short ones out, so a word typed
/// in Urdu cannot always be spelled back exactly: چاول is "chawl", not
/// "chawal". For that the search also compares SKELETONS — the key with its
/// vowels taken out ([spellingSkeleton]): چاول and chawal are both "cwl".
/// A skeleton is a much blunter instrument, so it is used only when it is
/// long enough to mean something (three consonants for a word typed in
/// Roman; two for one typed in Urdu, and then only when a vowel is plainly
/// missing from it) and its matches are ranked below everything else.
library;

/// What comes between the plain name and its key in `name_search`.
const String nameSearchSeparator = '|';

/// What comes between the key and its skeleton in `name_search`.
const String skeletonSeparator = '~';

/// `name_search` as it is stored on every item and every party: the plain
/// name, its spelling key, and the key's skeleton in capitals.
///
/// ```text
/// Atta Chakki 10kg  →  atta chakki 10kg|atacaki10kg~TCK10KG
/// آٹا               →  آٹا|ata~T
/// T.V. Stand        →  t v stand|twstand~TWSTND
/// ```
///
/// The plain name comes first so that `ORDER BY name_search` — which the
/// stock report and the low-stock list sort by — stays alphabetical by what
/// the shopkeeper typed.
///
/// The skeleton is stored rather than worked out in the query: working it
/// out costs four `replace()` calls on every row of a twenty-thousand-item
/// catalogue on every keystroke, which the counter measured at several
/// times the cost of the search itself. It is in capitals because the
/// search looks for parts with SQLite's `instr`, which is case-sensitive
/// and nothing else in the column is a capital: so a key is never found in
/// a skeleton ("tw", from "tv", is not in Tawa's "TW") and a skeleton is
/// never found in a key. None of the parts can contain either separator:
/// the plain name is letters, digits and spaces, the key is `a`–`z` and
/// `0`–`9`, and the skeleton `A`–`Z` and `0`–`9`.
String nameSearchColumn(String name) {
  final key = spellingKey(name);
  return '${plainSearchText(name)}$nameSearchSeparator$key'
      '$skeletonSeparator${spellingSkeleton(key).toUpperCase()}';
}

/// Lowercased, punctuation set aside, spaces collapsed — in any script.
///
/// What "the same name" means when the quick-add sheets look for a twin, and
/// the half of `name_search` an exact or a prefix match is read from. It
/// used to strip everything that was not an ASCII letter, which made every
/// name typed in Urdu an empty string: found by no search, and the twin of
/// nothing.
String plainSearchText(String text) => text
    .toLowerCase()
    .replaceAll(_notLetterOrDigit, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

/// The spelling key of [text]: every word's key, run together.
String spellingKey(String text) =>
    [for (final word in spellingWords(text)) word.key].join();

/// The key with its vowels taken out — what is left of a word when nobody
/// agrees how to spell it.
///
/// Taken from the KEY, not the text, and with no further folding, so the
/// skeleton of a name is the skeletons of its words run together and a
/// word's skeleton is always found inside its name's.
String spellingSkeleton(String key) => key.replaceAll(_keyVowels, '');

/// One word of a name or a search, as the search compares it.
final class SpellingWord {
  const SpellingWord({required this.key, required this.typedInUrdu});

  /// The word's spelling key. Never empty.
  final String key;

  /// Whether the word was typed in Urdu script, which decides how short a
  /// skeleton may be and still be trusted.
  final bool typedInUrdu;

  /// The skeleton the search may fall back on, or null when it would find
  /// more than it should.
  ///
  /// "cn" would find chini, chana and chaney alike; "cwl" finds chawal. So a
  /// word typed in Roman needs three consonants left. A word typed in Urdu
  /// needs two, but only when a short vowel is plainly missing from it — two
  /// consonants side by side, as in چاول (cawl) or گڑ (gr). چینی writes
  /// every vowel it has (cini), so its key already says all there is, and
  /// its skeleton "cn" would only add chana.
  String? get skeleton {
    final bones = spellingSkeleton(key);
    if (typedInUrdu) {
      return bones.length >= 2 && _shortVowelMissing.hasMatch(key)
          ? bones
          : null;
    }
    return bones.length >= 3 ? bones : null;
  }

  @override
  bool operator ==(Object other) =>
      other is SpellingWord &&
      other.key == key &&
      other.typedInUrdu == typedInUrdu;

  @override
  int get hashCode => Object.hash(key, typedInUrdu);

  @override
  String toString() => key;
}

/// The words of [text], each with its key, in order.
List<SpellingWord> spellingWords(String text) => [
  for (final word in text.toLowerCase().split(_wordBreak))
    if (_wordKey(urduToRoman(word)) case final key when key.isNotEmpty)
      SpellingWord(key: key, typedInUrdu: _arabicScript.hasMatch(word)),
];

/// What a shopkeeper typed into a search box, ready to be compared.
final class SpellingQuery {
  SpellingQuery._({
    required this.raw,
    required this.plain,
    required this.words,
  });

  factory SpellingQuery.of(String typed) {
    final raw = typed.trim();
    final words = spellingWords(raw);
    return SpellingQuery._(
      raw: raw,
      plain: plainSearchText(raw),
      // Five words is a long search. Each is another comparison on every
      // row, and nobody types a sixth word into a counter search box.
      words: List.unmodifiable(words.take(maxWords)),
    );
  }

  /// The most words a search compares.
  static const maxWords = 5;

  /// As typed, trimmed: what a code or a barcode is matched against.
  final String raw;

  /// [plainSearchText] of what was typed: what the exact and prefix tiers
  /// compare against the plain half of `name_search`.
  final String plain;

  /// The words, each with its key.
  final List<SpellingWord> words;

  /// The whole search as one key, for "the name starts with it".
  String get key => words.map((w) => w.key).join();

  bool get isEmpty => raw.isEmpty;
}

/// Urdu script read into Roman letters, so it can be keyed like the rest.
///
/// Deliberately simple — a table and three rules of context, not a
/// transliteration engine. It only has to land close enough that the
/// spelling key folds the two spellings together:
///
/// * و is "w" at the start of a word or beside an alif (چاول chawal, وارث
///   waris, دوا dwa), and "o" elsewhere (دودھ dodh, روٹی roti).
/// * ہ ending a word is "a", because that is the vowel it stands for:
///   زیرہ zeera, قیمہ qeema, میدہ maida.
/// * ی is "i" — cheeni and dahi are far commoner on a shop's shelves than
///   the "e" of tel — and ے is "e".
/// * ح, and a ہ inside a word, are an h that is sounded, and come out as a
///   capital H so the key keeps it even after a consonant: محمد is "mHmd".
///   Roman Urdu drops an h after a consonant because there it only marks a
///   breath (dhal, ghee) — which in Urdu script is ھ, and that is a plain
///   "h" and is dropped the same way. Without the difference محمد would key
///   as "md" and Muhammad could never find it.
///
/// Short vowels, which Urdu leaves unwritten, are left unwritten; the
/// skeleton comparison is what covers them. Diacritics are dropped, Urdu
/// and Arabic digits become 0–9, and Urdu punctuation becomes a space.
/// Text with no Arabic script in it comes back untouched.
String urduToRoman(String text) {
  if (!_arabicScript.hasMatch(text)) return text;
  final letters = [
    for (final c in text.runes)
      if (!_silent(c)) c,
  ];
  bool isLetter(int? c) =>
      c != null &&
      (_urdu.containsKey(c) ||
          c == _wao ||
          c == _goleHe ||
          c == _arabicHe ||
          (c >= 0x61 && c <= 0x7A) ||
          (c >= 0x30 && c <= 0x39));

  final out = StringBuffer();
  for (var i = 0; i < letters.length; i++) {
    final c = letters[i];
    final before = i > 0 ? letters[i - 1] : null;
    final after = i + 1 < letters.length ? letters[i + 1] : null;
    if (c == _wao) {
      final besideAlif = _alifs.contains(before) || _alifs.contains(after);
      out.write(!isLetter(before) || besideAlif ? 'w' : 'o');
    } else if (c == _goleHe || c == _arabicHe) {
      out.write(isLetter(after) || !isLetter(before) ? 'H' : 'a');
    } else if (_urdu[c] case final roman?) {
      out.write(roman);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out.writeCharCode(0x30 + c - 0x06F0);
    } else if (c >= 0x0660 && c <= 0x0669) {
      out.writeCharCode(0x30 + c - 0x0660);
    } else if (_arabicScript.hasMatch(String.fromCharCode(c))) {
      // Urdu punctuation (، ۔ ؟ ؛ ٪) and anything else in the block that is
      // not a letter separates words.
      out.write(' ');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// One word's key. See the library comment for the steps and why.
String _wordKey(String word) {
  var w = word.replaceAll(_notKeyable, '');
  if (w.isEmpty) return '';
  w = w.replaceAll('ee', 'i');
  w = _fold(w);
  w = w
      .replaceAll('eh', 'ah')
      .replaceAll('ae', 'ai')
      .replaceAll('q', 'k')
      .replaceAll(_hardC, 'k')
      .replaceAll('v', 'w')
      .replaceAllMapped(_hAfterConsonant, (m) => m[1]!);
  if (w.length > 1 && w.endsWith('h') && 'aeiouy'.contains(w[w.length - 2])) {
    w = w.substring(0, w.length - 1);
  }
  // A sounded Urdu h (see [urduToRoman]) has come through the rules above
  // untouched, and from here on is an h like any other.
  w = w.replaceAll('H', 'h');
  w = w.replaceAll('z', 'j').replaceAll('o', 'u').replaceAll('y', 'i');
  if (w.length > 2 && w.endsWith('ie')) w = w.substring(0, w.length - 1);
  return _fold(w);
}

/// A run of one letter, as one. Digits are left alone: 100 is not 10.
String _fold(String w) => w.replaceAllMapped(_doubled, (m) => m[1]!);

final _notLetterOrDigit = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);
final _spaces = RegExp(r'\s+', unicode: true);

/// Between words: anything that is not a letter, a digit, or one of the
/// three marks that join a word rather than end it (. - ').
final _wordBreak = RegExp(r"[^\p{L}\p{M}\p{N}.\-'’]+", unicode: true);
final _notKeyable = RegExp('[^a-z0-9H]');
final _doubled = RegExp(r'([a-z])\1+');
final _hardC = RegExp('c(?!h)');
final _hAfterConsonant = RegExp('([bcdfgjklmnpqrstvwxz])h');
final _keyVowels = RegExp('[aeiou]');
final _shortVowelMissing = RegExp('[bcdfghjklmnpqrstvwxz]{2}');
final _arabicScript = RegExp('[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

const _wao = 0x0648; // و
const _goleHe = 0x06C1; // ہ
const _arabicHe = 0x0647; // ه
const _alifs = {0x0627, 0x0622, 0x0623, 0x0625, 0x0671}; // ا آ أ إ ٱ

/// Marks that change how a letter is said but not which letter it is, the
/// kashida that only stretches a line, and the invisible joiners. Dropped
/// before anything else, so they never stand between a letter and the one
/// beside it.
bool _silent(int c) =>
    (c >= 0x064B && c <= 0x065F) ||
    c == 0x0670 ||
    (c >= 0x06D6 && c <= 0x06ED) ||
    c == 0x0640 ||
    c == 0x200C ||
    c == 0x200D;

/// Each Urdu letter, as Roman Urdu most often writes it.
const Map<int, String> _urdu = {
  0x0622: 'a', // آ
  0x0627: 'a', // ا
  0x0623: 'a', // أ
  0x0625: 'a', // إ
  0x0671: 'a', // ٱ
  0x0628: 'b', // ب
  0x067E: 'p', // پ
  0x062A: 't', // ت
  0x0679: 't', // ٹ
  0x062B: 's', // ث
  0x062C: 'j', // ج
  0x0686: 'ch', // چ
  0x062D: 'H', // ح
  0x062E: 'kh', // خ
  0x062F: 'd', // د
  0x0688: 'd', // ڈ
  0x0630: 'z', // ذ
  0x0631: 'r', // ر
  0x0691: 'r', // ڑ
  0x0632: 'z', // ز
  0x0698: 'zh', // ژ
  0x0633: 's', // س
  0x0634: 'sh', // ش
  0x0635: 's', // ص
  0x0636: 'z', // ض
  0x0637: 't', // ط
  0x0638: 'z', // ظ
  // ع is a vowel to a Roman typist far more often than not: Ali, Abbas,
  // Saad.
  0x0639: 'a', // ع
  0x063A: 'gh', // غ
  0x0641: 'f', // ف
  0x0642: 'q', // ق
  0x06A9: 'k', // ک
  0x0643: 'k', // ك
  0x06AF: 'g', // گ
  0x0644: 'l', // ل
  0x0645: 'm', // م
  0x0646: 'n', // ن
  0x06BA: 'n', // ں
  0x0624: 'o', // ؤ
  0x06C2: 'a', // ۂ
  0x06C3: 'a', // ۃ
  0x0629: 'a', // ة
  0x06BE: 'h', // ھ
  0x06CC: 'i', // ی
  0x064A: 'i', // ي
  0x0649: 'i', // ى
  0x0626: 'i', // ئ
  0x06D2: 'e', // ے
  0x06D3: 'e', // ۓ
  0x0621: '', // ء
};
