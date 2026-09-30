/// A delivery van's day, settled (M18).
///
/// A wholesaler in Shah Alam loads a van in the morning, the rider sells
/// from it along the route, and in the evening hands over the cash. What
/// the van's cash sales say the rider should have is set against what they
/// count out; the difference is the rider's short or over, booked where
/// the shop's own till differences are booked.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart';

/// Why a van action was refused, in words.
final class VanRefused implements Exception {
  const VanRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The stock location a van called [name] keeps its goods under.
///
/// `VAN-` and the name's letters and digits, upper-cased, so it reads on a
/// stock report; [taken] are codes already used, and a clash gets a number.
String vanLocationCode(String name, Set<String> taken) {
  final letters = name.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  final base = 'VAN-${letters.isEmpty ? '1' : letters}';
  var code = base;
  var n = 2;
  while (taken.contains(code)) {
    code = '$base-$n';
    n++;
  }
  return code;
}

/// The journal lines for a rider who counted [counted] against [expected],
/// or none when they match. Short is a cost (Dr Cash Short and Over, Cr
/// Cash); over is the other way.
List<JournalLinePosting> settlementLines({
  required Money expected,
  required Money counted,
  required String narration,
}) {
  final gap = counted - expected;
  if (gap.isZero) return const [];
  final amount = gap.abs;
  final short = gap.isNegative;
  return [
    JournalLinePosting(
      lineNo: 1,
      accountSystemKey: 'cash_short_over',
      debit: short ? amount : Money.zero,
      credit: short ? Money.zero : amount,
      narration: narration,
    ),
    JournalLinePosting(
      lineNo: 2,
      accountSystemKey: 'cash_in_hand',
      debit: short ? Money.zero : amount,
      credit: short ? amount : Money.zero,
      narration: narration,
    ),
  ];
}
