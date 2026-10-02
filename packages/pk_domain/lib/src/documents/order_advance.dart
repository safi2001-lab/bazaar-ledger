/// A sale order's advance, applied to the bill made from it (M41).
///
/// The advance itself is a receipt, taken through the receipt's own path
/// the day the customer placed the order and paid something down: money in
/// the drawer, and on the customer's khata as money the shop is holding
/// for them (Customer Advances, a liability — never a negative receivable).
/// Nothing about that is new.
///
/// What is new is the day the bill is made. Left alone, the bill would sit
/// on the khata as wholly owed beside an advance that nets it down, and
/// every per-bill list — the ageing, the due list, the bill itself — would
/// read the customer as owing what they had already paid. So the bill's
/// own entry takes the advance: of what it would have put on the khata as
/// udhaar, the part the advance covers is taken out of Customer Advances
/// instead, and the bill reads that much paid.
///
/// Inside the bill's own entry, and not a second one beside it, so that
/// every correction the app already has stays true without knowing about
/// orders: cancelling the bill mirrors its entry and the advance is held
/// again; cancelling the advance receipt mirrors the receipt and the khata
/// owes the bill in full; a bounced advance cheque takes back what it never
/// paid. No allocation row is written, because there is no payment for
/// this bill to carry — the money came in on the receipt, which stays as it
/// was.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart';

/// [posting] with [advance] taken off what its customer owes on it, from
/// the advance the shop holds for them against [orderNo].
///
/// Never more than the bill leaves owed: a bill paid in full at the counter
/// takes none of it, and the advance stays held for the customer.
SalePosting withOrderAdvance(
  SalePosting posting,
  Money advance, {
  required String orderNo,
}) {
  final doc = posting.document;
  final partyId = doc.partyId;
  final applied = advance > doc.balance ? doc.balance : advance;
  if (!applied.isPositive || partyId == null) return posting;

  final lines = <JournalLinePosting>[];
  var taken = false;
  for (final l in posting.journal.lines) {
    final isUdhaar =
        l.accountSystemKey == 'accounts_receivable' &&
        l.partyId == partyId &&
        l.debit >= applied;
    if (taken || !isUdhaar) {
      lines.add(l);
      continue;
    }
    taken = true;
    final rest = l.debit - applied;
    if (rest.isPositive) {
      lines.add(
        JournalLinePosting(
          lineNo: 0,
          accountSystemKey: l.accountSystemKey,
          debit: rest,
          credit: l.credit,
          partyId: l.partyId,
          itemId: l.itemId,
          narration: l.narration,
        ),
      );
    }
    lines.add(
      JournalLinePosting(
        lineNo: 0,
        accountSystemKey: 'customer_advances',
        debit: applied,
        credit: Money.zero,
        partyId: partyId,
        narration: 'Advance on $orderNo applied to ${doc.docNo}',
      ),
    );
  }
  if (!taken) {
    // The udhaar line is the builder's, and every bill that leaves anything
    // owed has one. A bill without it is not one this can safely change.
    throw StateError(
      'Bill ${doc.docNo} leaves ${doc.balance.amountOnly} owed with no '
      'udhaar line to take the advance off.',
    );
  }

  final entry = posting.journal;
  final adjusted = posting.copyWith(
    document: doc.settledBy(applied),
    journal: JournalEntryPosting(
      entryNo: entry.entryNo,
      entryDateUtcMillis: entry.entryDateUtcMillis,
      entryDateLocal: entry.entryDateLocal,
      fiscalYear: entry.fiscalYear,
      sourceType: entry.sourceType,
      totalDebit: entry.totalDebit,
      totalCredit: entry.totalCredit,
      narration: entry.narration,
      lines: [
        for (var i = 0; i < lines.length; i++)
          JournalLinePosting(
            lineNo: i + 1,
            accountSystemKey: lines[i].accountSystemKey,
            debit: lines[i].debit,
            credit: lines[i].credit,
            partyId: lines[i].partyId,
            itemId: lines[i].itemId,
            narration: lines[i].narration,
          ),
      ],
    ),
    auditSummary:
        '${posting.auditSummary}; advance ${applied.amountOnly} on $orderNo '
        'applied',
  );
  adjusted.assertBalanced();
  return adjusted;
}
