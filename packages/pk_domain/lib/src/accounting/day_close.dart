/// Closing the day: counting the drawer against what the books say is in it.
///
/// Every evening the shopkeeper counts the golak. The books already know
/// what should be there: every cash sale, every rupee of udhaar collected,
/// less every expense paid from it. When the two differ, the difference is
/// real, and the books are made to say what the drawer says, through a line
/// of its own so the shortfall is visible rather than absorbed.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// Why a day cannot be closed, in words.
final class DayCloseRefused implements Exception {
  const DayCloseRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Everything one day close writes.
final class DayClosePosting {
  const DayClosePosting({
    required this.expected,
    required this.counted,
    required this.journal,
    required this.auditSummary,
  });

  final Money expected;
  final Money counted;

  /// What was short (positive) or over (negative).
  Money get shortBy => expected - counted;

  /// Null when the drawer matched the books to the paisa.
  final JournalEntryPosting? journal;
  final String auditSummary;
}

/// Builds the rows a day close writes.
final class DayCloseBuilder {
  const DayCloseBuilder();

  DayClosePosting build({
    required ActorContext actor,
    required Money expected,
    required Money counted,
    AllocatedNumber? journalNumber,
    String? note,
  }) {
    if (counted.isNegative) {
      throw const DayCloseRefused('A drawer cannot hold less than nothing.');
    }
    final short = expected - counted;
    final day = actor.businessDate.value;
    final words = short.isZero
        ? 'matched the books'
        : short.isPositive
        ? 'short by ${short.amountOnly}'
        : 'over by ${(-short).amountOnly}';
    final remark = note == null || note.trim().isEmpty
        ? ''
        : ': ${note.trim()}';

    JournalEntryPosting? journal;
    if (!short.isZero) {
      if (journalNumber == null) {
        throw ArgumentError.notNull('journalNumber');
      }
      //   short:  Dr Cash Short and Over / Cr Cash in Hand
      //   over:   Dr Cash in Hand / Cr Cash Short and Over
      final amount = short.abs;
      final narration = 'Day close $day, drawer $words$remark';
      journal = JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.epochMillis,
        entryDateLocal: day,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'adjustment',
        totalDebit: amount,
        totalCredit: amount,
        narration: narration,
        lines: [
          JournalLinePosting(
            lineNo: 1,
            accountSystemKey: short.isPositive
                ? 'cash_short_over'
                : 'cash_in_hand',
            debit: amount,
            credit: Money.zero,
            narration: narration,
          ),
          JournalLinePosting(
            lineNo: 2,
            accountSystemKey: short.isPositive
                ? 'cash_in_hand'
                : 'cash_short_over',
            debit: Money.zero,
            credit: amount,
          ),
        ],
      );
    }
    return DayClosePosting(
      expected: expected,
      counted: counted,
      journal: journal,
      auditSummary:
          'Day $day closed: counted ${counted.amountOnly}, books said '
          '${expected.amountOnly}, $words$remark',
    );
  }
}
