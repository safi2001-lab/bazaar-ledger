/// Undoing a posted document without editing history.
///
/// A posted document is immutable. That is not a preference — a shopkeeper
/// has already printed it and handed the paper to a customer, and a number
/// that changes underneath somebody holding the receipt is the thing that
/// makes them stop trusting the app.
///
/// So a correction is a new entry that says the opposite, pointing at what it
/// undid. `journal_entries`, `journal_lines` and `stock_ledger` are
/// append-only and `TxRunner` refuses to update them; only `documents` moves,
/// and only its status.
///
/// ## Never a minus sign
///
/// The reversal swaps the sides. Every debit becomes a credit and every
/// credit becomes a debit, and no amount is ever negated.
///
/// Negating looks equivalent and is not. `assertBalanced` refuses a negative
/// amount and says why; the schema's own `CHECK (debit_paisa >= 0)` refuses
/// it three layers later as a constraint name with nothing in it a shopkeeper
/// could act on. And a Trial Balance built by summing a column cannot tell a
/// negative debit from a credit, so the report balances while the accounts
/// are wrong — which is the failure mode this whole layer exists to prevent.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// The mirror of [original], dated today.
///
/// Dated today rather than backdated to what it undoes, always. A reversal
/// backdated into a period that has been closed, reported or filed changes a
/// number somebody has already acted on; dated today it nets to zero in the
/// books and leaves both halves visible, which is what a day book should
/// show and what an auditor asks to see.
JournalEntryPosting reverseEntry(
  JournalEntryPosting original, {
  required ActorContext actor,
  required AllocatedNumber number,
  required String reason,
}) {
  if (original.lines.isEmpty) {
    throw ArgumentError.value(
      original.entryNo,
      'original',
      'an entry with no lines cannot be reversed, because nothing happened',
    );
  }

  final lines = <JournalLinePosting>[
    for (final line in original.lines)
      JournalLinePosting(
        lineNo: line.lineNo,
        accountSystemKey: line.accountSystemKey,
        // The swap. Not a negation — see the library comment.
        debit: line.credit,
        credit: line.debit,
        partyId: line.partyId,
        itemId: line.itemId,
        narration: line.narration,
      ),
  ];

  return JournalEntryPosting(
    entryNo: number.formatted,
    entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
    entryDateLocal: actor.businessDate.value,
    fiscalYear: actor.businessDate.fiscalYear,
    sourceType: 'reversal',
    totalDebit: original.totalCredit,
    totalCredit: original.totalDebit,
    narration: 'Reversal of ${original.entryNo}: $reason',
    lines: lines,
  );
}

/// The mirror of one stock movement.
///
/// At the ORIGINAL rate and the original value, never at today's average.
/// A void of a sale means the goods never left; putting them back at a cost
/// they were never carried at would change the shop's inventory value because
/// somebody corrected a typo, and the difference would land in no account at
/// all.
StockMovementPosting reverseMovement(
  StockMovementPosting original, {
  required ActorContext actor,
}) => StockMovementPosting(
  itemId: original.itemId,
  locationCode: original.locationCode,
  lotId: original.lotId,
  // Not `sale_return`. A return is a customer bringing goods back, which is a
  // different event with its own document and its own tax treatment. This is
  // a bill that should never have existed.
  txnType: 'adjustment',
  qtyDelta: Qty.raw(-original.qtyDelta.inThousandths),
  rate: original.rate,
  valueDelta: Money.paisa(-original.valueDelta.inPaisa),
  occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
  occurredOnLocal: actor.businessDate.value,
  lineNo: original.lineNo,
);

/// Why a document cannot be voided.
final class VoidRefused implements Exception {
  const VoidRefused(this.reason, {this.allocations = const []});

  final String reason;

  /// Payment numbers standing in the way, so the shopkeeper is told which
  /// receipts to deal with rather than being refused in the abstract.
  final List<String> allocations;

  @override
  String toString() => reason;
}

/// Everything voiding one document writes.
final class VoidPosting {
  const VoidPosting({
    required this.documentId,
    required this.docNo,
    required this.reason,
    required this.journal,
    required this.stockMovements,
    required this.reversesEntryId,
    required this.auditSummary,
  });

  final String documentId;
  final String docNo;
  final String reason;

  final JournalEntryPosting journal;
  final List<StockMovementPosting> stockMovements;

  /// What this undoes, recorded on the entry so the pair can always be found
  /// together. A reversal that does not point at its original is a second
  /// entry nobody can explain.
  final String reversesEntryId;

  final String auditSummary;

  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Voiding $docNo would post an unbalanced entry: debits '
        '${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Voiding $docNo line ${line.lineNo} carries a negative amount. A '
          'reversal swaps the sides; it never negates.',
        );
      }
    }
  }
}

/// Builds the reversal of a posted document.
final class VoidBuilder {
  const VoidBuilder();

  /// [allocatedPayments] is the receipt numbers already applied to this
  /// document.
  ///
  /// A void with allocations standing is REFUSED, not cleaned up quietly.
  /// The naive void leaves allocation rows pointing at a document that no
  /// longer exists as far as any report is concerned, and
  /// `findOverAllocatedPayments()` cannot catch it because the sum still
  /// fits — so the customer's khata quietly gains money nobody returned, and
  /// it surfaces months later as a balance nobody can explain.
  ///
  /// Refusing names the receipts, because "deal with the payments first" is
  /// only actionable if the shopkeeper is told which — and says where they
  /// are dealt with. The first version said "Undo those first" when nothing
  /// in the app could undo a payment; since M31 a receipt or a payment is
  /// opened from the khata's history and cancelled there, and the refusal
  /// says so.
  VoidPosting build({
    required ActorContext actor,
    required String documentId,
    required String docNo,
    required String reason,
    required JournalEntryPosting originalEntry,
    required String originalEntryId,
    required List<StockMovementPosting> originalMovements,
    required AllocatedNumber journalNumber,
    List<String> allocatedPayments = const [],
  }) {
    if (reason.trim().isEmpty) {
      // A void with no reason is a hole in the numbering that nobody can
      // account for six months later, and it is the first thing an auditor
      // asks about.
      throw const VoidRefused('A void has to say why.');
    }
    if (allocatedPayments.isNotEmpty) {
      final one = allocatedPayments.length == 1;
      throw VoidRefused(
        'Money has been recorded against $docNo: '
        '${allocatedPayments.join(', ')}. Cancel ${one ? 'that payment' : 'those payments'} '
        "first — open ${one ? 'it' : 'each'} in the khata's history and "
        'tap Cancel — or the khata keeps money nobody returned.',
        allocations: allocatedPayments,
      );
    }

    final posting = VoidPosting(
      documentId: documentId,
      docNo: docNo,
      reason: reason.trim(),
      journal: reverseEntry(
        originalEntry,
        actor: actor,
        number: journalNumber,
        // The document number as well as the reason. A narration reading
        // only "Reversal of JV-2627-00001" is useful to somebody who can
        // look up journal numbers, which is nobody standing at a counter —
        // the shopkeeper is looking for the bill.
        reason: '$docNo — ${reason.trim()}',
      ),
      stockMovements: [
        for (final m in originalMovements) reverseMovement(m, actor: actor),
      ],
      reversesEntryId: originalEntryId,
      auditSummary: 'Voided $docNo: ${reason.trim()}',
    );

    posting.assertBalanced();
    return posting;
  }
}
