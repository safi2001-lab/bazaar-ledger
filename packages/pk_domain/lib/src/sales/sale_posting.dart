import 'package:pk_money/pk_money.dart';

import '../mobile/qist.dart';
import '../pharmacy/medicine.dart';
import '../stock/lots.dart';
import '../tax/tax_charge.dart';

/// A row to be written to `documents`.
final class DocumentPosting {
  const DocumentPosting({
    required this.docType,
    required this.docNo,
    required this.docSeries,
    required this.docSeq,
    required this.fiscalYear,
    required this.docDateUtcMillis,
    required this.docDateLocal,
    required this.subtotal,
    required this.lineDiscount,
    required this.billDiscount,
    required this.taxable,
    required this.tax,
    required this.furtherTax,
    required this.withholding,
    required this.extraCharges,
    required this.roundOff,
    required this.total,
    required this.paid,
    required this.balance,
    required this.cost,
    required this.roundingMode,
    required this.taxRuleVersion,
    required this.cashThresholdBreached,
    this.partyId,
    this.partyNameSnapshot,
    this.partyNtnSnapshot,
    this.partyStrnSnapshot,
    this.partyAddressSnapshot,
    this.salespersonId,
    this.locationCode,
    this.notes,
    this.supplierBillNo,
    this.terms,
  });

  final String docType;
  final String docNo;
  final String docSeries;
  final int docSeq;
  final int fiscalYear;
  final int docDateUtcMillis;
  final String docDateLocal;

  final String? partyId;
  final String? partyNameSnapshot;
  final String? partyNtnSnapshot;
  final String? partyStrnSnapshot;
  final String? partyAddressSnapshot;

  final Money subtotal;
  final Money lineDiscount;
  final Money billDiscount;
  final Money taxable;
  final Money tax;
  final Money furtherTax;
  final Money withholding;
  final Money extraCharges;
  final Money roundOff;
  final Money total;
  final Money paid;
  final Money balance;
  final Money cost;

  final String roundingMode;
  final String taxRuleVersion;
  final bool cashThresholdBreached;
  final String? salespersonId;

  /// A van's location, or null for the shop floor.
  final String? locationCode;
  final String? notes;

  /// The number on the supplier's own paper, on a purchase bill. What they
  /// quote when they ring about an unpaid delivery.
  final String? supplierBillNo;

  /// Printed terms: how long a quotation's prices hold, and the like.
  final String? terms;

  /// This document with [amount] more paid on it and that much less owed,
  /// everything else as it was: a sale order's advance applied to the bill
  /// made from it (M41).
  DocumentPosting settledBy(Money amount) => DocumentPosting(
    docType: docType,
    docNo: docNo,
    docSeries: docSeries,
    docSeq: docSeq,
    fiscalYear: fiscalYear,
    docDateUtcMillis: docDateUtcMillis,
    docDateLocal: docDateLocal,
    subtotal: subtotal,
    lineDiscount: lineDiscount,
    billDiscount: billDiscount,
    taxable: taxable,
    tax: tax,
    furtherTax: furtherTax,
    withholding: withholding,
    extraCharges: extraCharges,
    roundOff: roundOff,
    total: total,
    paid: paid + amount,
    balance: balance - amount,
    cost: cost,
    roundingMode: roundingMode,
    taxRuleVersion: taxRuleVersion,
    cashThresholdBreached: cashThresholdBreached,
    partyId: partyId,
    partyNameSnapshot: partyNameSnapshot,
    partyNtnSnapshot: partyNtnSnapshot,
    partyStrnSnapshot: partyStrnSnapshot,
    partyAddressSnapshot: partyAddressSnapshot,
    salespersonId: salespersonId,
    locationCode: locationCode,
    notes: notes,
    supplierBillNo: supplierBillNo,
    terms: terms,
  );
}

/// A row to be written to `document_lines`, with its taxes.
final class DocumentLinePosting {
  const DocumentLinePosting({
    required this.lineNo,
    required this.itemNameSnapshot,
    required this.qty,
    required this.baseQty,
    required this.unitCodeSnapshot,
    required this.rate,
    required this.gross,
    required this.discount,
    required this.taxable,
    required this.tax,
    required this.lineTotal,
    required this.cost,
    required this.discountBp,
    required this.isFreeItem,
    required this.taxes,
    this.itemId,
    this.itemCodeSnapshot,
    this.hsCodeSnapshot,
    this.description,
    this.unitId,
    this.lotId,
    this.mrp,
  });

  final int lineNo;
  final String? itemId;
  final String itemNameSnapshot;
  final String? itemCodeSnapshot;
  final String? hsCodeSnapshot;
  final String? description;

  final Qty qty;
  final Qty baseQty;
  final String? unitId;
  final String unitCodeSnapshot;
  final Rate rate;
  final Money? mrp;
  final String? lotId;

  final Money gross;
  final int discountBp;
  final Money discount;
  final Money taxable;
  final Money tax;
  final Money lineTotal;
  final Money cost;
  final bool isFreeItem;

  final List<TaxCharge> taxes;
}

/// A row to be written to `payments`, plus its allocation to the document.
final class PaymentPosting {
  const PaymentPosting({
    required this.paymentNo,
    required this.direction,
    required this.paymentAccountId,
    required this.ledgerAccountId,
    required this.mode,
    required this.amount,
    required this.change,
    required this.paymentDateUtcMillis,
    required this.paymentDateLocal,
    this.partyId,
    this.tendered,
    this.reference,
    this.chequeNo,
    this.chequeBank,
    this.chequeDateUtcMillis,
    this.notes,
  });

  final String paymentNo;
  final String direction;
  final String paymentAccountId;

  /// Which account in the chart this tender lands in. Resolved from the
  /// payment account, so renaming "Golak" never breaks the posting.
  final String ledgerAccountId;

  final String mode;
  final Money amount;
  final Money? tendered;
  final Money change;
  final String? reference;
  final String? partyId;
  final int paymentDateUtcMillis;
  final String paymentDateLocal;

  final String? chequeNo;
  final String? chequeBank;
  final int? chequeDateUtcMillis;

  /// Words kept on the payment row: why udhaar was let go (M44).
  final String? notes;

  bool get isCheque => mode == 'cheque';
}

/// A row to be appended to `stock_ledger`.
final class StockMovementPosting {
  const StockMovementPosting({
    required this.itemId,
    required this.txnType,
    required this.qtyDelta,
    required this.valueDelta,
    required this.occurredAtUtcMillis,
    required this.occurredOnLocal,
    required this.lineNo,
    this.locationCode = 'MAIN',
    this.lotId,
    this.newLot,
    this.rate = Rate.zero,
  });

  final String itemId;
  final String locationCode;
  final String? lotId;

  /// A batch or serial arriving with this movement, which the writer finds
  /// or creates and puts this movement in.
  final LotDraft? newLot;
  final String txnType;

  /// In the item's base unit. Negative when stock leaves the shop.
  final Qty qtyDelta;

  final Rate rate;
  final Money valueDelta;
  final int occurredAtUtcMillis;
  final String occurredOnLocal;

  /// Which document line this movement came from, resolved to a real id when
  /// the posting is applied.
  final int lineNo;
}

/// One side of one journal line.
final class JournalLinePosting {
  const JournalLinePosting({
    required this.lineNo,
    required this.accountSystemKey,
    required this.debit,
    required this.credit,
    this.partyId,
    this.itemId,
    this.narration,
  });

  final int lineNo;

  /// Looked up by stable key, never by name or code, so renaming "Cash in
  /// Hand" to "Golak" cannot break a sale.
  final String accountSystemKey;

  final Money debit;
  final Money credit;
  final String? partyId;
  final String? itemId;
  final String? narration;
}

/// The journal entry a sale produces, with its lines.
final class JournalEntryPosting {
  const JournalEntryPosting({
    required this.entryNo,
    required this.entryDateUtcMillis,
    required this.entryDateLocal,
    required this.fiscalYear,
    required this.sourceType,
    required this.totalDebit,
    required this.totalCredit,
    required this.lines,
    this.narration,
  });

  final String entryNo;
  final int entryDateUtcMillis;
  final String entryDateLocal;
  final int fiscalYear;
  final String sourceType;
  final Money totalDebit;
  final Money totalCredit;
  final String? narration;
  final List<JournalLinePosting> lines;
}

/// Everything one sale writes, as a value.
///
/// The posting is computed before anything is written, which means the whole
/// of double entry can be asserted in a unit test with no database at all —
/// and means the write step has no decisions left to make and therefore no
/// room to make them differently.
final class SalePosting {
  const SalePosting({
    required this.document,
    required this.lines,
    required this.payments,
    required this.stockMovements,
    required this.journal,
    required this.auditSummary,
    this.convertedFromId,
    this.alsoFromIds = const [],
    this.replacesId,
    this.prescription,
    this.qist,
  });

  final DocumentPosting document;

  /// The qist plan the bill's balance is paid off by (M50), written with
  /// the bill in its own transaction.
  final QistPosting? qist;
  final List<DocumentLinePosting> lines;

  /// The prescription the bill's Schedule lines are registered against
  /// (M49).
  final Prescription? prescription;

  /// The document this bill was made from, linked `converted_from`.
  final String? convertedFromId;

  /// More challans on the same bill, each linked the same way (M25).
  final List<String> alsoFromIds;

  /// The cancelled bill this one puts right, linked `revises` (M36).
  final String? replacesId;
  final List<PaymentPosting> payments;
  final List<StockMovementPosting> stockMovements;
  final JournalEntryPosting journal;
  final String auditSummary;

  /// The same sale with any of its parts replaced, and every part not named
  /// carried as it was: a sale order's advance taken into the bill made from
  /// it (M41).
  ///
  /// It used to rebuild the posting from a list of the fields it meant to
  /// keep, and the list had missed one: a bill putting another right (M36)
  /// that was also made from a sale order lost its `revises` link to the
  /// bill it replaced on the way through. Every field is a parameter now,
  /// so a field added later is one the compiler shows here.
  SalePosting copyWith({
    DocumentPosting? document,
    List<DocumentLinePosting>? lines,
    List<PaymentPosting>? payments,
    List<StockMovementPosting>? stockMovements,
    JournalEntryPosting? journal,
    String? auditSummary,
    String? convertedFromId,
    List<String>? alsoFromIds,
    String? replacesId,
    Prescription? prescription,
    QistPosting? qist,
  }) => SalePosting(
    document: document ?? this.document,
    lines: lines ?? this.lines,
    payments: payments ?? this.payments,
    stockMovements: stockMovements ?? this.stockMovements,
    journal: journal ?? this.journal,
    auditSummary: auditSummary ?? this.auditSummary,
    convertedFromId: convertedFromId ?? this.convertedFromId,
    alsoFromIds: alsoFromIds ?? this.alsoFromIds,
    replacesId: replacesId ?? this.replacesId,
    prescription: prescription ?? this.prescription,
    qist: qist ?? this.qist, // M50
  );

  /// Asserts the entry balances, before anyone tries to write it.
  ///
  /// The database has a CHECK for this too, and [Tx] re-checks before commit.
  /// Three layers, because silent accounting wrongness is invisible for six
  /// months and then nothing balances and nobody can say when it started.
  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Sale ${document.docNo} would post an unbalanced journal entry: '
        'debits ${debit.amountOnly}, credits ${credit.amountOnly}, out by '
        '${(debit - credit).amountOnly}.',
      );
    }
    if (debit != journal.totalDebit || credit != journal.totalCredit) {
      throw StateError(
        'Sale ${document.docNo} declares totals that its own lines do not '
        'add up to.',
      );
    }
    // A negative debit is a credit wearing the wrong hat: the sums still
    // match, so the equality above passes, and the schema's own
    // `CHECK (debit_paisa >= 0)` then refuses the write three layers later as
    // a raw constraint error. Caught here instead, where the message can say
    // which line and why.
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Sale ${document.docNo} would post a negative amount to '
          '${line.accountSystemKey}: debit ${line.debit.amountOnly}, credit '
          '${line.credit.amountOnly}. An entry corrects itself with the '
          'opposite column, never with a minus sign.',
        );
      }
    }
  }
}
