/// Finding a bill again (M30).
///
/// The question a shop is asked about an old bill is never "show me the
/// newest forty". It is "Rashid Sahib's bill from last Tuesday", "the one for
/// fifty-five twenty-five", "the customer on 0300-447…". Until this the sales
/// list could only be scrolled, newest first, and a bill from last month was
/// a long way down a list with no handle on it.
///
/// Everything here is the meaning of what was typed and chosen. The read layer
/// turns it into a WHERE clause, so a filter narrows the rows SQLite returns
/// and paging carries on underneath it: a filter applied to one page in
/// memory would show "nothing found" for a bill that is simply on page three.
library;

import '../time/clock.dart';

/// Which bills, by where they stand.
enum SaleStanding {
  /// Every bill, cancelled ones included, as the list has always shown them.
  all,

  /// Standing bills with nothing left to pay.
  paid,

  /// Standing bills the customer still owes on.
  udhaar,

  /// Cancelled bills. Kept apart rather than hidden, because "did I cancel
  /// that one?" is a question asked of exactly this list.
  cancelled,
}

/// What the sales list is narrowed to.
///
/// A value: two filters that say the same thing are equal, so the list keyed
/// on one is the same list, and changing a chip back reuses what was read.
final class SaleFilter {
  const SaleFilter({
    this.query = '',
    this.from,
    this.to,
    this.standing = SaleStanding.all,
  });

  /// Nothing chosen: every bill, newest first.
  static const none = SaleFilter();

  /// A bill number, a customer's name, a phone number or an amount, as typed.
  final String query;

  /// The first business day included, or open-ended.
  final BusinessDate? from;

  /// The last business day included, or open-ended.
  final BusinessDate? to;

  final SaleStanding standing;

  /// What [query] could mean. See [SaleSearch].
  SaleSearch get search => SaleSearch.parse(query);

  bool get isNone =>
      query.trim().isEmpty &&
      from == null &&
      to == null &&
      standing == SaleStanding.all;

  SaleFilter copyWith({String? query, SaleStanding? standing}) => SaleFilter(
    query: query ?? this.query,
    from: from,
    to: to,
    standing: standing ?? this.standing,
  );

  /// The same filter over [from]..[to]; nulls open the range.
  SaleFilter between(BusinessDate? from, BusinessDate? to) =>
      SaleFilter(query: query, from: from, to: to, standing: standing);

  @override
  bool operator ==(Object other) =>
      other is SaleFilter &&
      other.query.trim() == query.trim() &&
      other.from == from &&
      other.to == to &&
      other.standing == standing;

  @override
  int get hashCode => Object.hash(query.trim(), from, to, standing);

  @override
  String toString() =>
      'SaleFilter("$query", ${from?.value}..${to?.value}, ${standing.name})';
}

/// One typed search, read every way a shopkeeper might have meant it.
///
/// A search box with one meaning makes the shopkeeper learn which one. This
/// one takes what they type and tries it as a bill number, a name, a phone
/// number and an amount at once, and a bill that matches any of them is
/// shown. Over-matching is the cheap direction here: one extra row in a list
/// is read past in a second, and a missing one is a bill "lost".
final class SaleSearch {
  const SaleSearch._({required this.text, this.phoneDigits, this.paisa});

  factory SaleSearch.parse(String raw) {
    final text = raw.trim();
    return SaleSearch._(
      text: text,
      phoneDigits: _phone(text),
      paisa: _amount(text),
    );
  }

  /// What was typed, trimmed. Matched inside the bill number and the name.
  final String text;

  /// The digits of a phone number, without the `0` or `92` in front, when
  /// what was typed could be one.
  ///
  /// Matched against the customer's number with its punctuation taken out,
  /// because `0300-4471203`, `0300 4471203` and `+92 300 4471203` are all
  /// how shops write the same number, and the one typed into the search box
  /// is never the one typed into the khata.
  final String? phoneDigits;

  /// The bill totals it could be, in paisa, both ends included.
  ///
  /// `5525` is every total from Rs 5,525.00 to Rs 5,525.99, because a
  /// shopkeeper says a bill's amount in rupees; `5525.50` is that one total.
  final (int, int)? paisa;

  bool get isEmpty => text.isEmpty;

  /// Fewer than four digits is too short to be anybody's number: `12` would
  /// match half the khata.
  static String? _phone(String text) {
    if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(text)) return null;
    var digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('92') && digits.length > 10) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits.length >= 4 ? digits : null;
  }

  /// Rupees, with or without the `Rs`, the thousands commas and the paisa.
  ///
  /// Whole paisa throughout, and never through a float: `5525.5` is 552550
  /// paisa because the digits say so, not because a double rounded to it.
  static (int, int)? _amount(String text) {
    final match = RegExp(
      r'^(?:rs\.?\s*)?([0-9][0-9,]*)(?:\.([0-9]{1,2}))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final rupeesText = match.group(1)!.replaceAll(',', '');
    // Past fifteen digits it is a barcode or a CNIC, not a bill, and it would
    // not fit in paisa either.
    if (rupeesText.isEmpty || rupeesText.length > 15) return null;
    final rupees = int.parse(rupeesText);
    final fraction = match.group(2);
    if (fraction == null) return (rupees * 100, rupees * 100 + 99);
    final paisa = rupees * 100 + int.parse(fraction.padRight(2, '0'));
    return (paisa, paisa);
  }
}

/// Who a document is addressed to, and where they can be reached.
///
/// Read separately from the receipt, deliberately. The receipt is the paper,
/// and it prints what it printed on the day; this is for sending it again,
/// which wants the customer's number as the khata has it now.
final class DocumentRecipient {
  const DocumentRecipient({
    required this.partyId,
    required this.name,
    this.phone,
  });

  final String partyId;
  final String name;

  /// As the shop wrote it down: their WhatsApp number when the khata has
  /// one, their phone otherwise. Not yet in the shape WhatsApp wants.
  final String? phone;
}
