/// Batches, expiry and serial numbers.
///
/// A pharmacy buys paracetamol in batches, each printed with its expiry, and
/// may not sell a strip past it. A mobile shop buys phones one IMEI at a
/// time and must be able to say which one went to whom. Both are the same
/// thing to the stock ledger: a lot, with its own balance, that goods come
/// into and go out of.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';

/// A lot as it arrives on a purchase line.
final class LotDraft {
  const LotDraft({
    required this.lotNo,
    this.batchNo,
    this.expiry,
    this.serial,
    this.mrp,
  });

  /// A batch number, or a serial number for a single piece.
  final String lotNo;
  final String? batchNo;
  final BusinessDate? expiry;
  final String? serial;

  /// The retail price printed on this batch, per base unit (M49). DRAP
  /// fixes it per batch: a price rise does not reach strips made before
  /// it, so two batches on one shelf can carry two prices.
  final Money? mrp;
}

/// What is left of one lot, where it is.
final class LotBalance {
  const LotBalance({
    required this.lotId,
    required this.lotNo,
    required this.qty,
    this.expiry,
    this.holdReason,
    this.mrp,
  });

  final String lotId;
  final String lotNo;
  final Qty qty;
  final BusinessDate? expiry;

  /// Why this batch may not be sold, while it may not (M49): a recall, a
  /// damaged carton. First-expiry-first-out passes it by.
  final String? holdReason;

  /// Its printed retail price per base unit, when the delivery said (M49).
  final Money? mrp;

  bool get isHeld => holdReason != null;

  bool isExpiredOn(BusinessDate today) =>
      expiry != null && expiry!.value.compareTo(today.value) < 0;
}

/// Why goods cannot be taken out of stock, in words.
final class StockRefused implements Exception {
  const StockRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// One part of a quantity taken out, and the lot it came from; a null lot
/// is stock that was never put into one (opening stock from before the item
/// was tracked by batch).
typedef LotTake = ({String? lotId, Qty qty});

/// Takes [needed] out of [lots] first-expiry-first-out.
///
/// Batches that expire soonest go first, then those with no expiry; stock
/// in no lot ([unlotted]) goes after every batch. A batch already past its
/// date is never taken: when only expired stock could make up the quantity,
/// the sale is refused and says which batch, because selling it is the one
/// thing a pharmacy's licence is lost over. A batch on hold (M49) is passed
/// by the same way, and refused in the words it was held with. Beyond what
/// is on the shelf the rest is taken from no lot, as the counter always
/// has, so a shop that never recorded its opening batches can still sell.
List<LotTake> takeFefo({
  required Qty needed,
  required List<LotBalance> lots,
  required Qty unlotted,
  required BusinessDate today,
}) {
  if (!needed.isPositive) return const [];
  final usable =
      lots
          .where((l) => l.qty.isPositive && !l.isExpiredOn(today) && !l.isHeld)
          .toList()
        ..sort((a, b) {
          final ea = a.expiry?.value ?? '9999-12-31';
          final eb = b.expiry?.value ?? '9999-12-31';
          final byExpiry = ea.compareTo(eb);
          return byExpiry != 0 ? byExpiry : a.lotNo.compareTo(b.lotNo);
        });
  final takes = <LotTake>[];
  var left = needed;
  for (final lot in usable) {
    if (!left.isPositive) break;
    final take = lot.qty < left ? lot.qty : left;
    takes.add((lotId: lot.lotId, qty: take));
    left -= take;
  }
  if (left.isPositive) {
    final expired = lots
        .where((l) => l.qty.isPositive && l.isExpiredOn(today))
        .toList();
    final fromNoLot = unlotted.isPositive
        ? (unlotted < left ? unlotted : left)
        : Qty.zero;
    if (expired.isNotEmpty && fromNoLot < left) {
      final first = expired.first;
      throw StockRefused(
        'Batch ${first.lotNo} expired on ${first.expiry!.value} and cannot '
        'be sold. Only ${(needed - left + fromNoLot).display} is in date.',
      );
    }
    // M49: a held batch is refused as an expired one is, in its own words.
    final held = lots
        .where((l) => l.qty.isPositive && l.isHeld && !l.isExpiredOn(today))
        .toList();
    if (held.isNotEmpty && fromNoLot < left) {
      throw StockRefused(
        heldBatchRefusal(held.first.lotNo, held.first.holdReason!),
      );
    }
    takes.add((lotId: null, qty: left));
  }
  return takes;
}

/// One lot still on the shelf, as the expiry list and the counter read it.
final class LotOnHand {
  const LotOnHand({
    required this.lotId,
    required this.itemId,
    required this.itemName,
    required this.lotNo,
    required this.qty,
    required this.cost,
    this.expiry,
    this.serial,
    this.holdReason,
    this.mrp,
  });

  final String lotId;
  final String itemId;
  final String itemName;
  final String lotNo;
  final Qty qty;

  /// Per base unit, as the lot came in.
  final Rate cost;
  final BusinessDate? expiry;
  final String? serial;

  /// Why it may not be sold, while it may not (M49).
  final String? holdReason;

  /// Its printed retail price per base unit, when the delivery said (M49).
  final Money? mrp;
}

/// Why a held batch is refused, in the words it was held with (M49).
String heldBatchRefusal(String lotNo, String reason) =>
    'Batch $lotNo is on hold and cannot be sold: $reason';
