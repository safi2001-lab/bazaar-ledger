/// Turning a supplier's bill into rows.
///
/// Pure. Given the bill, each item's costing position as it stands, and the
/// numbers already allocated, it produces every row the purchase writes,
/// moves each average, and proves the entry balances — with no database in
/// the way.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../mobile/imei.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../stock/lots.dart';
import '../time/clock.dart';
import 'moving_average.dart';
import 'purchase_posting.dart';

/// One line as the shopkeeper entered it.
final class PurchaseLineDraft {
  const PurchaseLineDraft({
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.baseQty,
    required this.unitId,
    required this.unitCode,
    required this.rate,
    this.batchNo,
    this.expiry,
    this.serials = const [],
    this.freeQty = Qty.zero,
    this.freeBaseQty = Qty.zero,
    this.mrp,
    this.phones = const [],
  });

  /// Phones, one per piece, in place of [serials] (M50): each by its IMEI,
  /// checked digit and all, with its second IMEI for the other SIM slot and
  /// what PTA said of it. A mistyped IMEI is refused here, beneath every
  /// screen; plain [serials] stay as M11 took them, because a television's
  /// serial number is not an IMEI.
  final List<PhoneUnitDraft> phones;

  final String itemId;
  final String itemName;

  /// The supplier's bonus on this line (M43): "10+1" is ten billed and one
  /// more that came free, in the same unit as [qty]. Zero on an ordinary
  /// line.
  ///
  /// The free goods go on the shelf and into the average with the paid ones
  /// and carry their cost: ten cartons at Rs 960 with one free is eleven
  /// cartons for Rs 9,600, and each costs Rs 872.73. The line's money is
  /// what the supplier billed and nothing else. Written as a line of its own
  /// beside the paid one, marked free, so the delivery reads like the
  /// supplier's paper and a return of the free carton credits nothing.
  final Qty freeQty;

  /// [freeQty] in the item's base unit.
  final Qty freeBaseQty;

  /// Whether the supplier sent anything free on this line.
  bool get hasFree => freeBaseQty.isPositive;

  /// Everything this line puts on the shelf, paid and free.
  Qty get shelfQty => baseQty + freeBaseQty;

  /// The retail price printed on the batch, per base unit (M49). Kept on
  /// the batch, because DRAP fixes it batch by batch.
  final Money? mrp;

  /// The batch printed on the goods, for an item kept by batch.
  final String? batchNo;

  /// When that batch expires.
  final BusinessDate? expiry;

  /// One serial number per piece, for an item kept by serial: as many as
  /// [baseQty] counts pieces.
  final List<String> serials;

  /// As billed — bori, carton, whatever the supplier writes.
  final Qty qty;

  /// The same quantity in the item's base unit. Converted before it gets
  /// here, because two maunds is eighty kilos and the stock ledger only ever
  /// speaks kilos.
  final Qty baseQty;

  final String unitId;
  final String unitCode;

  /// Per billed unit, not per base unit.
  final Rate rate;

  Money get lineTotal => rate.amountFor(qty);
}

/// One line of a delivery, landed: what it cost with its share of the
/// freight, and what that did to the item's average.
final class LandedLine {
  const LandedLine({
    required this.landed,
    required this.before,
    required this.change,
  });

  final Money landed;
  final CostPosition before;
  final CostChange change;
}

/// What each line of [draft] does to the cost of the goods it carries, in
/// order.
///
/// The one place this is worked out. The builder posts from it, and the
/// purchase screen shows the new average per line from it, so the figure a
/// shopkeeper watches move as they type is the figure that gets written.
List<LandedLine> landLines(
  PurchaseDraft draft,
  Map<String, CostPosition> positions,
) {
  // Freight across the lines by value, using the allocator that cannot lose
  // a paisa. Splitting it evenly would put as much delivery cost on a Rs 50
  // packet as on a Rs 5,000 sack.
  final shares = draft.freight.isZero || draft.lines.isEmpty
      ? [for (final _ in draft.lines) Money.zero]
      : draft.freight.allocate([
          for (final l in draft.lines) l.lineTotal.inPaisa,
        ]);

  // Carried between lines, so a bill with the same item twice — a real thing
  // on a wholesale delivery — averages the second line against the first
  // rather than against the shelf as it was this morning.
  final running = <String, CostPosition>{...positions};

  return [
    for (var i = 0; i < draft.lines.length; i++)
      () {
        final line = draft.lines[i];
        final landed = line.lineTotal + shares[i];
        final before = running[line.itemId] ?? CostPosition.zero;
        // The free goods (M43) arrive with the paid ones, in one step, so
        // the average falls by exactly what they bring and the paid goods'
        // money is spread over both.
        final change = receiveStock(
          before: before,
          qtyIn: line.shelfQty,
          landedCost: landed,
        );
        running[line.itemId] = change.after;
        return LandedLine(landed: landed, before: before, change: change);
      }(),
  ];
}

/// A supplier's bill.
final class PurchaseDraft {
  const PurchaseDraft({
    required this.partyId,
    required this.lines,
    this.supplierBillNo,
    this.freight = Money.zero,
    this.paid = Money.zero,
    this.paymentAccountId,
    this.notes,
    this.fromOrderId,
  });

  /// Always a supplier. A purchase with no party is stock that appeared from
  /// nowhere, and the shop cannot pay or query it.
  final String partyId;

  final List<PurchaseLineDraft> lines;

  /// The supplier's own number, which is what the shopkeeper matches against
  /// the paper. Never used for numbering — that series is the shop's.
  final String? supplierBillNo;

  /// Delivery, labour, the rickshaw. Apportioned across the lines by value,
  /// because it is what the goods cost to have on the shelf and a margin
  /// computed against the invoice alone has never paid for delivery.
  final Money freight;

  /// Paid at the door. The rest is payable.
  final Money paid;
  final String? paymentAccountId;

  final String? notes;

  /// The purchase order this delivery arrived against (M41), linked
  /// `converted_from` so the order knows what of it has come in. A delivery
  /// against no order leaves it null, as every delivery before M41 did.
  final String? fromOrderId;

  Money get goodsTotal => Money.sum([for (final l in lines) l.lineTotal]);
  Money get total => goodsTotal + freight;
}

/// Builds the rows one purchase bill writes.
final class PurchaseBuilder {
  const PurchaseBuilder();

  /// [positions] is each item's costing as it stands, keyed by item id.
  /// [ledgerAccountId] is where any cash paid at the door comes from.
  PurchasePosting build({
    required ActorContext actor,
    required PurchaseDraft draft,
    required Map<String, CostPosition> positions,
    required AllocatedNumber billNumber,
    required AllocatedNumber journalNumber,
    String? ledgerAccountId,
  }) {
    if (draft.lines.isEmpty) {
      throw ArgumentError.value(
        draft.lines.length,
        'lines',
        'a bill with no lines is not a delivery',
      );
    }
    if (draft.paid.isNegative) {
      throw ArgumentError.value(
        draft.paid.inPaisa,
        'paid',
        'a negative payment is a refund and has its own path',
      );
    }
    if (draft.paid > draft.total) {
      // Not an advance to the supplier: that is a payment out with no bill,
      // and it belongs on the supplier's khata rather than inflating what
      // this delivery cost.
      throw ArgumentError.value(
        draft.paid.inPaisa,
        'paid',
        'more was paid than the bill is for. Money handed over beyond a bill '
            'is an advance to the supplier, not part of this delivery.',
      );
    }
    if (draft.paid.isPositive && ledgerAccountId == null) {
      throw ArgumentError.value(
        ledgerAccountId,
        'ledgerAccountId',
        'money was paid at the door and there is no account it came out of',
      );
    }

    final landedLines = landLines(draft, positions);

    final lines = <PurchaseLinePosting>[];
    final movements = <StockMovementPosting>[];
    var rounding = Money.zero;
    var shortfall = Money.zero;
    var inventoryDelta = Money.zero;

    // Rows are numbered as they are written: a line the supplier sent
    // something free on is two rows (M43), so the row number runs ahead of
    // the line number from there on.
    var rowNo = 0;

    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final LandedLine(:landed, :before, :change) = landedLines[i];
      // Same subtraction, two accounts. A shortfall this delivery covered is
      // a real loss the books never took; anything else is a rounding step.
      if (change.fromShortfall) {
        shortfall += change.adjustment;
      } else {
        rounding += change.adjustment;
      }
      inventoryDelta += change.after.value - before.value;

      // M50: a line of phones names each by IMEI 1, and refuses a mistyped
      // one, or one number given for two phones, before anything is built.
      for (final phone in line.phones) {
        phone.check();
      }
      final phoneNumbers = [for (final p in line.phones) ...p.imeis];
      if (phoneNumbers.toSet().length != phoneNumbers.length) {
        throw StockRefused('${line.itemName}: the same IMEI is given twice.');
      }
      final serials = line.phones.isNotEmpty
          ? [for (final p in line.phones) p.imeis.first]
          : [
              for (final s in line.serials)
                if (s.trim().isNotEmpty) s.trim(),
            ];
      if (line.freeQty.isNegative || line.freeBaseQty.isNegative) {
        throw StockRefused(
          '${line.itemName}: free goods cannot be less than nothing.',
        );
      }
      if (line.hasFree && serials.isNotEmpty) {
        // A free phone is still a phone with its own number, and a line of
        // serials names exactly the pieces it paid for.
        throw StockRefused(
          '${line.itemName} is kept by serial number. A piece that came '
          'free needs its own serial on its own line.',
        );
      }

      // The paid goods and the free ones share what the line landed at, by
      // quantity, to the paisa: each carton of "10+1" costs an eleventh of
      // the ten's money (M43). Without free goods the paid row takes it all.
      final shares = line.hasFree
          ? landed.allocate([
              line.baseQty.inThousandths,
              line.freeBaseQty.inThousandths,
            ])
          : [landed];
      final paidNo = ++rowNo;

      lines.add(
        PurchaseLinePosting(
          lineNo: paidNo,
          itemId: line.itemId,
          itemName: line.itemName,
          qty: line.qty,
          unitId: line.unitId,
          unitCode: line.unitCode,
          baseQty: line.baseQty,
          rate: line.rate,
          lineTotal: line.lineTotal,
          landedCost: shares.first,
          avgAfter: change.after.avg,
          balanceAfter: change.after.qty,
        ),
      );

      if (serials.isNotEmpty) {
        // One movement per piece, each in a lot of its own named by its
        // serial, so the counter can later say which one it sold.
        if (!line.baseQty.isWhole ||
            line.baseQty.inThousandths ~/ 1000 != serials.length) {
          throw StockRefused(
            '${line.itemName}: ${line.baseQty.display} pieces need '
            '${line.baseQty.display} serial numbers, and '
            '${serials.length} were given.',
          );
        }
        if (serials.toSet().length != serials.length) {
          throw StockRefused(
            '${line.itemName}: the same serial number is given twice.',
          );
        }
        final values = landed.split(serials.length);
        for (var k = 0; k < serials.length; k++) {
          movements.add(
            StockMovementPosting(
              itemId: line.itemId,
              txnType: 'purchase',
              qtyDelta: Qty.one,
              rate: change.after.avg,
              valueDelta: values[k],
              occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
              occurredOnLocal: actor.businessDate.value,
              lineNo: paidNo,
              newLot: LotDraft(
                lotNo: serials[k],
                serial: serials[k],
                // M50: the phone's second IMEI and its PTA standing.
                serial2: line.phones.isEmpty
                    ? null
                    : line.phones[k].imeis.skip(1).firstOrNull,
                pta: line.phones.isEmpty ? null : line.phones[k].pta,
              ),
            ),
          );
        }
      } else {
        final batch = line.batchNo?.trim();
        // The free goods go into the same batch as the paid ones: they came
        // in the same cartons.
        final lot = batch == null || batch.isEmpty
            ? null
            : LotDraft(
                lotNo: batch,
                batchNo: batch,
                expiry: line.expiry,
                // M49: the price printed on the batch.
                mrp: line.mrp,
              );
        movements.add(
          StockMovementPosting(
            itemId: line.itemId,
            txnType: 'purchase',
            qtyDelta: line.baseQty,
            rate: change.after.avg,
            valueDelta: shares.first,
            occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
            occurredOnLocal: actor.businessDate.value,
            lineNo: paidNo,
            newLot: lot,
          ),
        );
        if (line.hasFree) {
          final freeNo = ++rowNo;
          lines.add(
            PurchaseLinePosting(
              lineNo: freeNo,
              itemId: line.itemId,
              itemName: line.itemName,
              qty: line.freeQty,
              unitId: line.unitId,
              unitCode: line.unitCode,
              baseQty: line.freeBaseQty,
              rate: Rate.zero,
              lineTotal: Money.zero,
              landedCost: shares.last,
              avgAfter: change.after.avg,
              balanceAfter: change.after.qty,
              isFree: true,
            ),
          );
          movements.add(
            StockMovementPosting(
              itemId: line.itemId,
              txnType: 'purchase',
              qtyDelta: line.freeBaseQty,
              rate: change.after.avg,
              valueDelta: shares.last,
              occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
              occurredOnLocal: actor.businessDate.value,
              lineNo: freeNo,
              newLot: lot,
            ),
          );
        }
      }
    }

    final journalLines = <JournalLinePosting>[];
    var lineNo = 1;

    void post({
      required String key,
      Money debit = Money.zero,
      Money credit = Money.zero,
      String? partyId,
      String? narration,
    }) {
      if (debit.isZero && credit.isZero) return;
      journalLines.add(
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: key,
          debit: debit,
          credit: credit,
          partyId: partyId,
          narration: narration,
        ),
      );
    }

    // Dr Inventory by what the shelf is actually worth now, minus what it was
    // worth before. NOT by the landed cost: when the balance was negative the
    // account really did hold that negative figure, and debiting the landed
    // cost would assume it started at zero.
    post(
      key: 'inventory',
      debit: inventoryDelta.isPositive ? inventoryDelta : Money.zero,
      credit: inventoryDelta.isNegative ? inventoryDelta.abs : Money.zero,
      narration: 'Goods received ${billNumber.formatted}',
    );

    // A shortfall this delivery covered. The shop sold goods it had never
    // recorded receiving, so the books carried them out at the old average;
    // the delivery reveals what they actually cost, and the difference was
    // never anybody's profit.
    post(
      key: 'stock_wastage',
      debit: shortfall.isPositive ? shortfall : Money.zero,
      credit: shortfall.isNegative ? shortfall.abs : Money.zero,
      narration: 'Shortfall settled by ${billNumber.formatted}',
    );

    // The paisa induction could not place. Signed either way, so it is a
    // debit or a credit rather than a negative.
    post(
      key: 'cogs',
      debit: rounding.isPositive ? rounding : Money.zero,
      credit: rounding.isNegative ? rounding.abs : Money.zero,
      narration: 'Rounding on ${billNumber.formatted}',
    );

    // What was handed over at the door, and what is still owed.
    post(
      key: '#$ledgerAccountId',
      credit: draft.paid,
      narration: 'Paid on ${billNumber.formatted}',
    );
    post(
      key: 'accounts_payable',
      credit: draft.total - draft.paid,
      partyId: draft.partyId,
      narration: 'Owed on ${billNumber.formatted}',
    );

    final debits = Money.sum([for (final l in journalLines) l.debit]);
    final credits = Money.sum([for (final l in journalLines) l.credit]);

    final posting = PurchasePosting(
      document: DocumentPosting(
        docType: 'purchase_bill',
        docNo: billNumber.formatted,
        docSeries: billNumber.series,
        docSeq: billNumber.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        docDateLocal: actor.businessDate.value,
        subtotal: draft.goodsTotal,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: draft.goodsTotal,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: draft.freight,
        roundOff: Money.zero,
        total: draft.total,
        paid: draft.paid,
        balance: draft.total - draft.paid,
        cost: Money.sum([for (final l in lines) l.landedCost]),
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        partyId: draft.partyId,
        notes: draft.notes,
        supplierBillNo: draft.supplierBillNo?.trim().isEmpty ?? true
            ? null
            : draft.supplierBillNo!.trim(),
      ),
      lines: lines,
      stockMovements: movements,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'purchase',
        totalDebit: debits,
        totalCredit: credits,
        narration: 'Purchase ${billNumber.formatted}',
        lines: journalLines,
      ),
      rounding: rounding,
      shortfall: shortfall,
      fromOrderId: draft.fromOrderId,
      auditSummary:
          'Purchase ${billNumber.formatted} for ${draft.total.amountOnly} '
          'across ${lines.length} line(s)'
          '${draft.supplierBillNo == null ? '' : ', supplier bill '
                    '${draft.supplierBillNo}'}',
    );

    posting.assertBalanced();
    return posting;
  }
}
