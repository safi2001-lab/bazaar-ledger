/// "Ghar le gaye": goods off the shop's shelf for the home (M47).
///
/// A tin of ghee, a sack of atta, a carton of soap for the house. The goods
/// leave the shelf exactly as if they were sold, and nobody pays for them:
/// they are the owner taking his share of the shop in kind. So they leave
/// at what they cost, never at the sale price (the margin was never made),
/// and the cost goes to Owner's Drawings, not to wastage or an expense:
///
///   Dr  Owner's Drawings   the goods, at their average cost
///     Cr  Inventory        the goods, at their average cost
///
/// with the stock row that takes them off the shelf.
///
/// ## Why not the stock adjustment
///
/// `adjustStock` (M1) posts every movement against Stock Wastage, and its
/// rows belong to no document, so cancelling one is a second adjustment
/// counted by hand. Here the goods leave on an `expense` document of the
/// home's — the same kind as the home's cash spending — with its journal
/// entry and its stock row both tied to it. M31's cancel then undoes both
/// in one act: the void writer mirrors the entry and puts the goods back
/// on the shelf at the cost they left at, as it does for a sale bill.
///
/// Only from the shop floor, and only goods kept by the piece or weight:
/// an item kept by batch or serial number would have to say which batch
/// went home, and that is a stock adjustment's job.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/expense_builder.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// What the owner took home.
final class GoodsTakenHomeDraft {
  const GoodsTakenHomeDraft({
    required this.itemId,
    required this.qty,
    this.note = '',
  });

  final String itemId;

  /// In the item's base unit.
  final Qty qty;

  /// Anything to add: "Eid ke liye".
  final String note;
}

/// The item as the writer read it inside the transaction.
final class HomeGoodsItem {
  const HomeGoodsItem({
    required this.name,
    required this.unitCode,
    required this.averageCost,
    required this.onHand,
    required this.tracksStock,
    required this.tracksLots,
  });

  final String name;
  final String unitCode;
  final Rate averageCost;
  final Qty onHand;
  final bool tracksStock;

  /// Kept by batch or by serial number.
  final bool tracksLots;
}

/// Everything taking goods home writes.
final class HomeGoodsPosting {
  const HomeGoodsPosting({
    required this.document,
    required this.journal,
    required this.movement,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final JournalEntryPosting journal;
  final StockMovementPosting movement;
  final String auditSummary;

  Money get value => document.total;
}

/// Builds the rows taking [draft] home writes, or refuses in words.
HomeGoodsPosting goodsTakenHome({
  required ActorContext actor,
  required GoodsTakenHomeDraft draft,
  required HomeGoodsItem item,
  required AllocatedNumber number,
  required AllocatedNumber journalNumber,
  required String drawingsAccountId,
  required String inventoryAccountId,
}) {
  if (!item.tracksStock) {
    throw ExpenseRefused(
      '${item.name} is not kept in stock, so nothing comes off the shelf. '
      'Enter what it cost as ghar ka kharcha instead.',
    );
  }
  if (item.tracksLots) {
    throw ExpenseRefused(
      '${item.name} is kept by batch or serial number. Take it off the '
      'shelf with a stock adjustment, which asks which one.',
    );
  }
  if (!draft.qty.isPositive) {
    throw const ExpenseRefused('Say how much was taken home.');
  }
  if (draft.qty.inThousandths > item.onHand.inThousandths) {
    throw ExpenseRefused(
      'The books show ${item.onHand.display} ${item.unitCode} of ${item.name} '
      'on the shelf, less than ${draft.qty.display}. Count the shelf first.',
    );
  }
  final value = item.averageCost.amountFor(draft.qty);
  if (!value.isPositive) {
    throw ExpenseRefused(
      '${item.name} has no cost in the books yet, so there is nothing to put '
      "against the owner's share. Record a purchase of it first.",
    );
  }

  final note = draft.note.trim();
  final what =
      'Ghar le gaye: ${draft.qty.display} ${item.unitCode} ${item.name}'
      '${note.isEmpty ? '' : ' — $note'}';
  final millis = actor.epochMillis;
  final today = actor.businessDate;

  return HomeGoodsPosting(
    document: DocumentPosting(
      docType: 'expense',
      docNo: number.formatted,
      docSeries: number.series,
      docSeq: number.sequence,
      fiscalYear: today.fiscalYear,
      docDateUtcMillis: millis,
      docDateLocal: today.value,
      subtotal: value,
      lineDiscount: Money.zero,
      billDiscount: Money.zero,
      taxable: value,
      tax: Money.zero,
      furtherTax: Money.zero,
      withholding: Money.zero,
      extraCharges: Money.zero,
      roundOff: Money.zero,
      total: value,
      paid: value,
      balance: Money.zero,
      cost: value,
      roundingMode: 'half_up',
      taxRuleVersion: '',
      cashThresholdBreached: false,
      notes: what,
    ),
    journal: JournalEntryPosting(
      entryNo: journalNumber.formatted,
      entryDateUtcMillis: millis,
      entryDateLocal: today.value,
      fiscalYear: today.fiscalYear,
      sourceType: 'expense',
      totalDebit: value,
      totalCredit: value,
      narration: 'Ghar ka kharcha ${number.formatted}: $what',
      lines: [
        JournalLinePosting(
          lineNo: 1,
          accountSystemKey: '#$drawingsAccountId',
          debit: value,
          credit: Money.zero,
          itemId: draft.itemId,
          narration: what,
        ),
        JournalLinePosting(
          lineNo: 2,
          accountSystemKey: '#$inventoryAccountId',
          debit: Money.zero,
          credit: value,
          itemId: draft.itemId,
          narration: 'Ghar ka kharcha ${number.formatted}',
        ),
      ],
    ),
    movement: StockMovementPosting(
      itemId: draft.itemId,
      // Not `wastage`: nothing was lost. Not `sale`: nothing was sold. The
      // shelf was corrected for a known reason, which the row carries.
      txnType: 'adjustment',
      qtyDelta: Qty.raw(-draft.qty.inThousandths),
      rate: item.averageCost,
      valueDelta: Money.paisa(-value.inPaisa),
      occurredAtUtcMillis: millis,
      occurredOnLocal: today.value,
      lineNo: 1,
    ),
    auditSummary:
        'Ghar ka kharcha ${number.formatted}: $what, '
        'Rs ${value.amountOnly} at cost',
  );
}
