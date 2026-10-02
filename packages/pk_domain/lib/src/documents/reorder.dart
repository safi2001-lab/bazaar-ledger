/// What to order, and who from (M41).
///
/// Two lists feed it. The shelf's own: every item at or below the floor the
/// shop set for it, with M34's reorder quantity (the average day's selling
/// times the days an order has to last, less the shelf, never less than
/// back up to the floor) — computed by the very function the Low Stock
/// report prints, never a second copy of it. And the counter's: the
/// shortage list, the "*" a cashier writes when a customer asks for
/// something the shelf does not have, which Marg calls the shortage book and
/// which in most bazaar shops is the back page of the khata register.
///
/// Whatever is already on a purchase order still to arrive comes off, so
/// the same forty bori are not ordered twice because the first lot is on a
/// truck. What is left is grouped by the supplier each item last came
/// from, because that is who the order-booker is, and one tap makes one
/// purchase order per supplier.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'orders.dart';

/// One item the shop could order now.
final class ReorderLine {
  const ReorderLine({
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitCode,
    required this.qty,
    this.stock = Qty.zero,
    this.minStock = Qty.zero,
    this.sold = Qty.zero,
    this.onOrder = Qty.zero,
    this.asked = Qty.zero,
    this.wasAsked = false,
    this.supplierId,
    this.supplierName,
    this.rate,
  });

  final String itemId;
  final String itemName;

  /// The item's own unit, which everything here is counted in.
  final String unitId;
  final String unitCode;

  /// What to order: suggested, until the shopkeeper changes it.
  final Qty qty;

  final Qty stock;
  final Qty minStock;

  /// Sold over the days the suggestion looked back over.
  final Qty sold;

  /// Already on a purchase order still to arrive.
  final Qty onOrder;

  /// What customers asked for at the counter, when the shortage list had a
  /// quantity for it.
  final Qty asked;

  /// Whether it is on the shortage list at all.
  final bool wasAsked;

  /// Who the last delivery of it came from, if anybody.
  final String? supplierId;
  final String? supplierName;

  /// What it last cost a unit, from that supplier: the rate the purchase
  /// order quotes back to them.
  final Rate? rate;

  Money get value => rate == null ? Money.zero : rate!.amountFor(qty);

  ReorderLine copyWith({
    Qty? qty,
    String? supplierId,
    String? supplierName,
    Rate? rate,
  }) => ReorderLine(
    itemId: itemId,
    itemName: itemName,
    unitId: unitId,
    unitCode: unitCode,
    qty: qty ?? this.qty,
    stock: stock,
    minStock: minStock,
    sold: sold,
    onOrder: onOrder,
    asked: asked,
    wasAsked: wasAsked,
    supplierId: supplierId ?? this.supplierId,
    supplierName: supplierName ?? this.supplierName,
    rate: rate ?? this.rate,
  );

  /// The line as a purchase order carries it.
  OrderLineDraft toOrderLine() => OrderLineDraft(
    itemId: itemId,
    itemName: itemName,
    qty: qty,
    baseQty: qty,
    unitId: unitId,
    unitCode: unitCode,
    rate: rate ?? Rate.zero,
  );
}

/// How much of an item to order now (M41): what the shelf needs, as M34's
/// reorder quantity says, less what is already on its way; and at least
/// what a customer asked for that is not already on its way. Never below
/// nothing.
Qty orderToPlace({
  required Qty needed,
  required Qty onOrder,
  Qty asked = Qty.zero,
}) {
  final forShelf = needed - onOrder;
  final forCustomer = asked - onOrder;
  final want = forShelf > forCustomer ? forShelf : forCustomer;
  return want.isPositive ? want : Qty.zero;
}

/// The items to order from one supplier, or from nobody known yet.
final class ReorderGroup {
  const ReorderGroup({required this.lines, this.supplierId, this.supplierName});

  /// Null for items never bought from anybody through this app: the
  /// shopkeeper picks who to order them from.
  final String? supplierId;
  final String? supplierName;
  final List<ReorderLine> lines;

  Money get value => Money.sum([for (final l in lines) l.value]);
}

/// [lines] grouped by the supplier each last came from, suppliers by name
/// and items by name within each; items with no supplier come last, as one
/// group.
List<ReorderGroup> groupBySupplier(Iterable<ReorderLine> lines) {
  final bySupplier = <String, List<ReorderLine>>{};
  final names = <String, String>{};
  final orphans = <ReorderLine>[];
  for (final l in lines) {
    final id = l.supplierId;
    if (id == null) {
      orphans.add(l);
    } else {
      bySupplier.putIfAbsent(id, () => []).add(l);
      names[id] = l.supplierName ?? '';
    }
  }
  int byName(ReorderLine a, ReorderLine b) =>
      a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
  final ids = bySupplier.keys.toList()
    ..sort(
      (a, b) => names[a]!.toLowerCase().compareTo(names[b]!.toLowerCase()),
    );
  return [
    for (final id in ids)
      ReorderGroup(
        supplierId: id,
        supplierName: names[id],
        lines: bySupplier[id]!..sort(byName),
      ),
    if (orphans.isNotEmpty) ReorderGroup(lines: orphans..sort(byName)),
  ];
}

/// One thing a customer asked for that the shelf did not have: a line on
/// the shortage list.
final class ShortageEntry {
  const ShortageEntry({
    required this.id,
    required this.name,
    required this.addedOn,
    this.itemId,
    this.qty,
    this.unitCode,
    this.note,
    this.addedBy,
  });

  final String id;

  /// What was asked for: the item's name, or the customer's own words when
  /// it is not something the shop has ever kept.
  final String name;

  /// The item, when it is one the shop keeps. Only these can go on a
  /// purchase order; the rest are read out to the order-booker.
  final String? itemId;
  final Qty? qty;
  final String? unitCode;
  final String? note;
  final BusinessDate addedOn;

  /// Who wrote it down.
  final String? addedBy;
}

/// A line to add to the shortage list.
final class ShortageDraft {
  const ShortageDraft({
    required this.name,
    this.itemId,
    this.qty,
    this.unitCode,
    this.note,
  });

  final String name;
  final String? itemId;
  final Qty? qty;
  final String? unitCode;
  final String? note;
}

/// The words a purchase order travels in on WhatsApp (M41): what is wanted,
/// how many, at what rate, and by when, in the Roman Urdu the shop and its
/// suppliers write to each other in.
///
/// [lines] are what is still to come, each `(name, qty, unit, rate)`. The
/// rate is quoted back so the bill the supplier writes can be held to it.
String purchaseOrderMessage({
  required String shopName,
  required String docNo,
  required List<({String name, Qty qty, String unit, Rate rate})> lines,
  String? supplierName,
  BusinessDate? due,
  String? notes,
}) {
  final buffer = StringBuffer();
  final name = supplierName?.trim();
  buffer.write(
    name == null || name.isEmpty
        ? 'Assalam-o-Alaikum,\n\n'
        : 'Assalam-o-Alaikum $name,\n\n',
  );
  buffer.write('$shopName ka order $docNo:\n');
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    buffer.write('${i + 1}. ${l.name}: ${l.qty.display} ${l.unit}');
    if (!l.rate.isZero) buffer.write(' @ Rs ${l.rate.amountOnly}');
    buffer.write('\n');
  }
  if (due != null) buffer.write('${due.value} tak bhej dein.\n');
  final note = notes?.trim();
  if (note != null && note.isNotEmpty) buffer.write('Note: $note\n');
  buffer.write('\nShukriya.');
  return buffer.toString();
}

/// The shortage list in words, to send to the owner or read to the
/// order-booker.
String shortageMessage({
  required String shopName,
  required List<ShortageEntry> entries,
}) {
  final buffer = StringBuffer('$shopName: mangwana hai\n');
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    buffer.write('${i + 1}. ${e.name}');
    if (e.qty case final q?) {
      buffer.write(
        ': ${q.display}${e.unitCode == null ? '' : ' ${e.unitCode}'}',
      );
    }
    final note = e.note?.trim();
    if (note != null && note.isNotEmpty) buffer.write(' ($note)');
    buffer.write('\n');
  }
  return buffer.toString().trimRight();
}
