/// What the goods on a shelf actually cost the shop.
///
/// `avg_cost_milli_paisa` is written once when an item is created and has
/// never moved since. Until it does, every margin figure in this app is a
/// guess: a shop that opened an item at Rs 90 and has been buying at Rs 120
/// for six months still reads a Rs 30 profit on every sale.
///
/// ## Weighted average, and why not FIFO
///
/// A kiryana shop does not know which sack of rice it sold. The stock is in a
/// bin, the new delivery goes on top of the old, and nobody is tracking
/// layers. Weighted average is what the shopkeeper already does in their
/// head, it survives a stock-take, and it needs no lot tracking — which lands
/// in M11 for the pharmacies that genuinely need it.
///
/// ## The invariant, and why it is by induction
///
/// After every movement:
///
///     inventoryValuePaisa == divideRounded(avg * qty, 1_000_000, halfUp)
///
/// Held forward from the previous state, never recomputed by re-summing the
/// stock ledger. Re-summing looks safer and is not: it makes today's cost a
/// function of every row ever written, so one bad historical row silently
/// restates last month's profit, and a shop with three years of movements
/// pays for the whole history on every sale.
///
/// The price of induction is drift, and the fix is the residue line below.
library;

import 'package:pk_money/pk_money.dart';

/// The state of one item's costing, before or after a movement.
final class CostPosition {
  const CostPosition({
    required this.qty,
    required this.value,
    required this.avg,
  });

  /// What is on the shelf.
  final Qty qty;

  /// What it is carried at, in whole paisa. Stored alongside [avg] rather
  /// than derived from it, because the two disagree by a rounding step and
  /// the ledger has to be told which one it is.
  final Money value;

  /// Cost per base unit, in milli-paisa.
  final Rate avg;

  static const zero = CostPosition(
    qty: Qty.zero,
    value: Money.zero,
    avg: Rate.raw(0),
  );
}

/// What a receipt of goods does to an item's cost.
final class CostChange {
  const CostChange({
    required this.after,
    required this.residue,
    required this.writeOff,
  });

  final CostPosition after;

  /// The paisa that induction lost or gained on this movement.
  ///
  /// Posted as one extra journal line against COGS. Without it, Inventory
  /// drifts a paisa at a time away from `round(avg x qty)` and after a year
  /// nobody can say when it started; with it, the tie-out is an exact
  /// equality a test can assert. Usually zero.
  final Money residue;

  /// Stock that was owed and has now been supplied.
  ///
  /// A negative balance means the shop sold something it never recorded
  /// receiving. When the delivery lands, that shortfall is written off to
  /// wastage in the same entry rather than being carried into the average —
  /// where it would make the new stock look cheaper than it was, forever.
  final Money writeOff;
}

/// Applies a receipt of [qtyIn] at [landedCost] to [before].
///
/// [landedCost] is the total for the whole receipt including whatever the
/// shop paid to get it there — freight, labour, the rickshaw. Per-receipt
/// rather than per-unit, because that is the number on the bill and dividing
/// it into a per-unit rate first throws away the paisa the residue exists to
/// catch.
CostChange receiveStock({
  required CostPosition before,
  required Qty qtyIn,
  required Money landedCost,
}) {
  if (!qtyIn.isPositive) {
    throw ArgumentError.value(
      qtyIn.inThousandths,
      'qtyIn',
      'a receipt of nothing is not a receipt. A return out is a movement in '
          'the other direction and has its own path.',
    );
  }
  if (landedCost.isNegative) {
    throw ArgumentError.value(
      landedCost.inPaisa,
      'landedCost',
      'goods that arrive cannot cost less than nothing',
    );
  }

  final qtyAfter = Qty.raw(before.qty.inThousandths + qtyIn.inThousandths);

  // A shortfall the delivery has just covered. Written off rather than
  // averaged in: the shop sold goods it never recorded receiving, and letting
  // that absence dilute the new cost would make everything on the shelf look
  // cheaper than it was.
  final writeOff = before.qty.inThousandths < 0 ? before.value.abs : Money.zero;

  final Rate avgAfter;
  if (before.qty.isPositive) {
    // The weighted step. Guarded before it multiplies, because avg is in
    // milli-paisa and qty in thousandths, so the product is six orders of
    // magnitude above the rupee figure a shopkeeper would recognise and
    // wraps at int64 long before anything looks wrong.
    final carried = scaleOrThrow(
      before.avg.inMilliPaisa,
      before.qty.inThousandths.abs(),
      'carried inventory value',
    );
    final incoming = scaleOrThrow(landedCost.inPaisa, 1000000, 'landed cost');
    avgAfter = Rate.raw(
      divideRounded(
        carried + incoming,
        qtyAfter.inThousandths,
        RoundingMode.halfUp,
      ),
    );
  } else {
    // Nothing on the shelf, or less than nothing. Either way the new stock
    // sets the cost by itself: there is no old stock to weight it against,
    // and the shortfall above is not a negative purchase.
    avgAfter = Rate.raw(
      divideRounded(
        scaleOrThrow(landedCost.inPaisa, 1000000, 'landed cost'),
        qtyIn.inThousandths,
        RoundingMode.halfUp,
      ),
    );
  }

  final valueBefore = before.qty.isPositive ? before.value : Money.zero;
  final valueAfter = avgAfter.amountFor(qtyAfter);
  final residue = valueBefore + landedCost - valueAfter;

  return CostChange(
    after: CostPosition(qty: qtyAfter, value: valueAfter, avg: avgAfter),
    residue: residue,
    writeOff: writeOff,
  );
}

/// Applies an issue of [qtyOut] — a sale, a wastage, a transfer out.
///
/// The average does NOT move. That is the whole point of weighted average and
/// the most common thing to get wrong: an issue takes stock out at the cost
/// it is carried at, and changing the cost because something left would make
/// a sale profitable by selling.
CostChange issueStock({required CostPosition before, required Qty qtyOut}) {
  if (!qtyOut.isPositive) {
    throw ArgumentError.value(
      qtyOut.inThousandths,
      'qtyOut',
      'an issue of nothing is not an issue',
    );
  }

  final qtyAfter = Qty.raw(before.qty.inThousandths - qtyOut.inThousandths);

  // At zero the average is KEPT, not cleared. A zero here posts zero COGS on
  // the next sale after the next delivery is entered a minute late, and a
  // sale with no cost is a sale with infinite margin in every report that
  // reads it.
  final avgAfter = before.avg;

  final valueAfter = qtyAfter.inThousandths == 0
      ? Money.zero
      : avgAfter.amountFor(qtyAfter);
  final issuedAt = avgAfter.amountFor(qtyOut);
  final residue = before.value - issuedAt - valueAfter;

  return CostChange(
    after: CostPosition(qty: qtyAfter, value: valueAfter, avg: avgAfter),
    residue: residue,
    writeOff: Money.zero,
  );
}
