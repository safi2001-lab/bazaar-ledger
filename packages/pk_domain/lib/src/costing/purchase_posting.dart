/// A delivery arriving, described before any of it is written.
///
/// The same shape as a sale and a receipt: the rows are a value, the entry is
/// proved to balance while it is still a value, and a use case that wrote
/// nothing has nothing to return.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart';

/// One line of a supplier's bill.
final class PurchaseLinePosting {
  const PurchaseLinePosting({
    required this.lineNo,
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.unitId,
    required this.unitCode,
    required this.baseQty,
    required this.rate,
    required this.lineTotal,
    required this.landedCost,
    required this.avgAfter,
    required this.balanceAfter,
  });

  final int lineNo;
  final String itemId;
  final String itemName;

  /// As entered — bori, carton, whatever the supplier billed in.
  final Qty qty;
  final String unitId;
  final String unitCode;

  /// The same quantity in the item's base unit, which is the only unit the
  /// stock ledger and the average ever see.
  final Qty baseQty;

  final Rate rate;
  final Money lineTotal;

  /// [lineTotal] plus this line's share of freight and other charges. What
  /// the goods actually cost to have on the shelf, and what the average is
  /// computed from.
  final Money landedCost;

  /// The item's new average cost, and its new balance, after this line.
  final Rate avgAfter;
  final Qty balanceAfter;
}

/// Everything one purchase bill writes.
final class PurchasePosting {
  const PurchasePosting({
    required this.document,
    required this.lines,
    required this.stockMovements,
    required this.journal,
    required this.auditSummary,
    required this.rounding,
    required this.shortfall,
  });

  final DocumentPosting document;
  final List<PurchaseLinePosting> lines;
  final List<StockMovementPosting> stockMovements;
  final JournalEntryPosting journal;
  final String auditSummary;

  /// The paisa induction lost or gained across every line, posted to COGS.
  final Money rounding;

  /// What this delivery revealed a past shortfall really cost, posted to
  /// wastage. Zero on any bill that did not land on a negative balance.
  final Money shortfall;

  /// Asserts the entry balances, before anyone tries to write it.
  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Purchase ${document.docNo} would post an unbalanced entry: '
        'debits ${debit.amountOnly}, credits ${credit.amountOnly}, out by '
        '${(debit - credit).amountOnly}.',
      );
    }
    if (debit != journal.totalDebit || credit != journal.totalCredit) {
      throw StateError(
        'Purchase ${document.docNo} declares totals its own lines do not add '
        'up to.',
      );
    }
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Purchase ${document.docNo} line ${line.lineNo} carries a negative '
          'amount. A reversal swaps the sides; it never negates.',
        );
      }
    }

    // What the shop is carrying has to be what it paid, allowing for the
    // paisa induction could not place. A balanced journal cannot catch this
    // on its own: both sides can come from the same wrong total.
    final landed = Money.sum([for (final l in lines) l.landedCost]);
    if (landed != document.total) {
      throw StateError(
        'Purchase ${document.docNo} lands ${landed.amountOnly} of goods '
        'against a bill of ${document.total.amountOnly}.',
      );
    }
  }
}
