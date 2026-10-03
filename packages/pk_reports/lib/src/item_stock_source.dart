import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// The rows behind the item and stock reports (M34), and the reads that
/// fetch them.
///
/// Every quantity is in the item's base unit and comes off the stock
/// ledger, the one place the shop's stock is written; every value at cost
/// is the ledger's own `value_delta_paisa`, the figure each movement moved
/// through Inventory in the books when it happened. A report built from
/// these rows therefore lands on the books' Inventory to the paisa, rather
/// than on a guess at today's average cost.

/// One item's stock at the close of a day: what is on the shelf and what
/// the books carry it at.
final class StockLine {
  const StockLine({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.saleRate,
    required this.averageCost,
    required this.qty,
    required this.value,
    this.category,
    this.taxBp = 0,
    this.priceIncludesTax = false,
  });

  final String itemId;
  final String itemName;
  final String unitCode;

  /// `items.category`, or null when it has none.
  final String? category;

  /// What it sells for now, per base unit.
  final Rate saleRate;

  /// The item's own sales-tax rate, in basis points; nothing when it has
  /// no tax rule (M67).
  final int taxBp;

  /// Whether [saleRate] already has the tax in it (M67).
  final bool priceIncludesTax;

  /// The weighted-average cost the item carries now, per base unit: what a
  /// line with nothing on the shelf is shown at.
  final Rate averageCost;

  /// On the shelf at the close of the day; less than nothing when more was
  /// sold than was recorded coming in.
  final Qty qty;

  /// What the books carry that stock at: every movement's value to the day.
  final Money value;

  /// The cost of one unit as the books carry the stock: its value over its
  /// quantity, or the item's own average when there is nothing to divide.
  Rate get unitCost => qty.isPositive
      ? Rate.fromPack(value, qty, mode: RoundingMode.halfUp)
      : averageCost;

  /// The shelf valued as [valuation] says (M67): at cost the books' own
  /// figure, with the item's tax added for cost with tax; at the sale
  /// price, the stock times it, with the tax taken out of a price that
  /// includes it, or put on one that does not.
  Money valueAt(StockValuation valuation) {
    Money withTax(Money m) => m + m.percentBp(taxBp);
    Money withoutTax(Money m) => taxBp == 0
        ? m
        : Money.paisa(
            divideRounded(
              m.inPaisa * 10000,
              10000 + taxBp,
              RoundingMode.halfUp,
            ),
          );
    final atPrice = saleRate.amountFor(qty);
    return switch (valuation) {
      StockValuation.cost => value,
      StockValuation.costWithTax => withTax(value),
      StockValuation.salePrice =>
        priceIncludesTax ? withoutTax(atPrice) : atPrice,
      StockValuation.salePriceWithTax =>
        priceIncludesTax ? atPrice : withTax(atPrice),
    };
  }
}

/// How much of an item moved, and why, over some stretch of days (M34).
///
/// Each figure is the size of the movement the way a shopkeeper says it:
/// twelve sold, three sent back. Only [adjusted] carries a sign, because a
/// count can find more on the shelf as easily as less.
final class StockMoves {
  const StockMoves({
    this.purchased = Qty.zero,
    this.returnsIn = Qty.zero,
    this.transfersIn = Qty.zero,
    this.produced = Qty.zero,
    this.sold = Qty.zero,
    this.returnsOut = Qty.zero,
    this.transfersOut = Qty.zero,
    this.used = Qty.zero,
    this.wasted = Qty.zero,
    this.adjusted = Qty.zero,
  });

  static const none = StockMoves();

  /// Deliveries from suppliers.
  final Qty purchased;

  /// Goods customers brought back.
  final Qty returnsIn;

  /// Moved here from another place: a godown, a van.
  final Qty transfersIn;

  /// Made in a production run.
  final Qty produced;

  /// Sold, on a bill or a challan that stands.
  final Qty sold;

  /// Sent back to suppliers.
  final Qty returnsOut;

  /// Moved from here to another place.
  final Qty transfersOut;

  /// Used up as a component in a production run.
  final Qty used;

  /// Written off: broken, spoilt, expired.
  final Qty wasted;

  /// Counted in or out by hand, opening stock entered in the period, and
  /// the goods of a cancelled bill going out and coming back.
  final Qty adjusted;

  /// Into stock, every way but an adjustment.
  Qty get totalIn => purchased + returnsIn + transfersIn + produced;

  /// Out of stock, every way but an adjustment.
  Qty get totalOut => sold + returnsOut + transfersOut + used + wasted;

  /// What the shelf gained, all told.
  Qty get net => totalIn - totalOut + adjusted;

  StockMoves operator +(StockMoves o) => StockMoves(
    purchased: purchased + o.purchased,
    returnsIn: returnsIn + o.returnsIn,
    transfersIn: transfersIn + o.transfersIn,
    produced: produced + o.produced,
    sold: sold + o.sold,
    returnsOut: returnsOut + o.returnsOut,
    transfersOut: transfersOut + o.transfersOut,
    used: used + o.used,
    wasted: wasted + o.wasted,
    adjusted: adjusted + o.adjusted,
  );
}

/// One item over a period, for the stock detail: what it opened with, how
/// it moved, and the value the movements took through Inventory (M34).
final class StockFlow {
  const StockFlow({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.openingQty,
    required this.openingValue,
    required this.moves,
    required this.movedValue,
    this.category,
  });

  final String itemId;
  final String itemName;
  final String unitCode;
  final String? category;

  /// On the shelf at the close of the day before the period began.
  final Qty openingQty;

  /// What the books carried it at then.
  final Money openingValue;
  final StockMoves moves;

  /// What the period's movements of it added to Inventory, less what they
  /// took out.
  final Money movedValue;
}

/// One day of one item's stock (M34).
final class ItemDay {
  const ItemDay({required this.date, required this.moves});

  final BusinessDate date;
  final StockMoves moves;
}

/// One item's stock, day by day, over a period (M34).
final class ItemHistory {
  const ItemHistory({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.openingQty,
    required this.days,
  });

  final String itemId;
  final String itemName;
  final String unitCode;

  /// On the shelf at the close of the day before the period began.
  final Qty openingQty;

  /// Each day in the period on which it moved, oldest first.
  final List<ItemDay> days;
}

/// What one item did on the bills of a period, both ways (M34).
///
/// The amounts are the lines' own: before tax and after every discount,
/// with the bill's discount already apportioned to each line by the
/// calculator that printed it. A return is the return's own line.
final class ItemTrade {
  const ItemTrade({
    required this.itemName,
    required this.unitCode,
    this.itemId,
    this.category,
    this.qtySold = Qty.zero,
    this.qtyReturned = Qty.zero,
    this.salesGross = Money.zero,
    this.discount = Money.zero,
    this.sales = Money.zero,
    this.returns = Money.zero,
    this.cost = Money.zero,
    this.returnedCost = Money.zero,
    this.qtyBought = Qty.zero,
    this.qtySentBack = Qty.zero,
    this.purchases = Money.zero,
    this.purchaseReturns = Money.zero,
    this.qtyBonus = Qty.zero,
  });

  /// What every line with no item behind it is called, together: khula
  /// maal sold by the rupee (M37), which moved no stock and recorded no
  /// cost.
  static const looseLines = 'Khula maal (no item)';

  /// Null for the one row of [looseLines].
  final String? itemId;

  /// Whether this is the row of lines with no item: no unit to count them
  /// in and no cost on record.
  bool get isLoose => itemId == null;
  final String itemName;
  final String unitCode;
  final String? category;
  final Qty qtySold;

  /// Brought back by customers.
  final Qty qtyReturned;

  /// What the sold lines came to at their rate, before any discount.
  final Money salesGross;

  /// What came off the sold lines: each line's own discount and its share
  /// of the bill's.
  final Money discount;

  /// What the sold lines came to before tax, after every discount.
  final Money sales;

  /// What the returned lines took back, the same way.
  final Money returns;

  /// What the goods sold cost when they left the shelf, as each line
  /// recorded it.
  final Money cost;

  /// What the goods brought back cost, as each return recorded it.
  final Money returnedCost;
  final Qty qtyBought;

  /// Sent back to suppliers.
  final Qty qtySentBack;

  /// Deliveries before tax.
  final Money purchases;
  final Money purchaseReturns;

  /// Given free under the shop's schemes (M43): part of [qtySold], since it
  /// left the shelf on a bill, and at no price, so nothing of it is in the
  /// sales or the discount.
  final Qty qtyBonus;

  Qty get netQtySold => qtySold - qtyReturned;
  Money get netSales => sales - returns;
  Money get netCost => cost - returnedCost;
  Money get profit => netSales - netCost;
  Qty get netQtyBought => qtyBought - qtySentBack;
  Money get netPurchases => purchases - purchaseReturns;
}

/// One party's trade in one item over a period, net of returns (M34). A
/// walk-in is a party with no id.
final class ItemPartyTrade {
  const ItemPartyTrade({
    required this.name,
    required this.qtySold,
    required this.saleAmount,
    required this.qtyBought,
    required this.purchaseAmount,
    this.partyId,
  });

  final String? partyId;
  final String name;

  /// To the party, less what they brought back.
  final Qty qtySold;

  /// Before tax, after every discount, less returns.
  final Money saleAmount;

  /// From the party, less what went back to them.
  final Qty qtyBought;
  final Money purchaseAmount;
}

/// An item at or below the floor the shop set for it (M34).
final class LowStockLine {
  const LowStockLine({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.minStock,
    required this.stock,
    required this.sold,
    this.category,
    this.lastSupplier,
  });

  final String itemId;
  final String itemName;
  final String unitCode;
  final String? category;
  final Qty minStock;
  final Qty stock;

  /// Sold over the days the report looks back over, less what came back.
  final Qty sold;

  /// Who the last delivery of it came from.
  final String? lastSupplier;
}

/// One batch on the shelf (M34).
final class BatchLine {
  const BatchLine({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.lotNo,
    required this.qty,
    required this.value,
    this.expiry,
    this.mrp,
  });

  final String itemId;
  final String itemName;
  final String unitCode;

  /// The batch as the shop knows it.
  final String lotNo;
  final BusinessDate? expiry;

  /// The price printed on this batch, which a pharmacy may not sell above.
  final Money? mrp;
  final Qty qty;

  /// What the books carry what is left of the batch at: its own rows'
  /// value, so the batches of an item add up to the item's.
  final Money value;
}

/// One serial-numbered piece: a phone by its IMEI, a fan by its number
/// (M34). Where it came from, and where it went.
final class SerialLine {
  const SerialLine({
    required this.serial,
    required this.itemId,
    required this.itemName,
    required this.onHand,
    this.lastOut,
    this.supplier,
    this.boughtOn,
    this.customer,
    this.soldOn,
    this.saleId,
    this.saleNo,
    this.saleType,
    this.returnedOn,
  });

  final String serial;
  final String itemId;
  final String itemName;

  /// One while it is here, nothing once it has gone.
  final Qty onHand;

  /// How it last left: `sale`, `purchase_return`, `wastage`...
  final String? lastOut;

  /// Who it was bought from, and when it came in.
  final String? supplier;
  final BusinessDate? boughtOn;

  /// Who it was last sold to, when, and on which paper.
  final String? customer;
  final BusinessDate? soldOn;
  final String? saleId;
  final String? saleNo;

  /// `sale_invoice`, or `delivery_challan` for one that left on a challan.
  final String? saleType;

  /// When a customer last brought it back.
  final BusinessDate? returnedOn;
}

/// Goods moved from one place to another (M34).
final class StockTransferLine {
  const StockTransferLine({
    required this.date,
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.qty,
    required this.from,
    required this.to,
    required this.value,
  });

  final BusinessDate date;
  final String itemId;
  final String itemName;
  final String unitCode;
  final Qty qty;

  /// Where they left and where they arrived: a location code, or a van's
  /// name.
  final String from;
  final String to;

  /// What they were carried at, at the item's average cost.
  final Money value;
}

/// One component a production run used (M34).
final class RunComponent {
  const RunComponent({
    required this.itemName,
    required this.unitCode,
    required this.qty,
  });

  final String itemName;
  final String unitCode;
  final Qty qty;
}

/// One production run (M34).
final class ProductionRun {
  const ProductionRun({
    required this.date,
    required this.runNo,
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.qty,
    required this.componentsCost,
    required this.overhead,
    this.components = const [],
  });

  final BusinessDate date;
  final String runNo;
  final String itemId;

  /// The finished item.
  final String itemName;
  final String unitCode;

  /// Made, in the finished item's base unit.
  final Qty qty;
  final List<RunComponent> components;

  /// What the components cost as they left the shelf.
  final Money componentsCost;

  /// Work, packets and gas, on top.
  final Money overhead;

  Money get totalCost => componentsCost + overhead;
}

/// How one item has been selling (M34): for the fast, slow and dead stock.
final class ItemSelling {
  const ItemSelling({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.bills,
    required this.qtySold,
    required this.stock,
    required this.value,
    this.category,
    this.lastSold,
  });

  final String itemId;
  final String itemName;
  final String unitCode;
  final String? category;

  /// Bills it was on over the days looked back over.
  final int bills;

  /// Sold over those days, less what came back.
  final Qty qtySold;

  /// The last day it was sold, ever.
  final BusinessDate? lastSold;
  final Qty stock;

  /// What the books carry the stock at.
  final Money value;
}

/// How long one item's stock has been on the shelf (M34).
///
/// [buckets] are the quantity in each age band, 0 to 45 days, 46 to 90,
/// 91 to 180 and over 180, found by matching what is on the shelf to the
/// latest receipts first: what first came in is what first went out.
final class ItemAgeing {
  const ItemAgeing({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.onHand,
    required this.value,
    required this.buckets,
    this.category,
  });

  final String itemId;
  final String itemName;
  final String unitCode;
  final String? category;
  final Qty onHand;

  /// What the books carry the stock at.
  final Money value;

  /// The quantity in each age band, youngest first; four of them.
  final List<Qty> buckets;
}

/// Where the item and stock reports read from (M34).
///
/// Each read narrows by the [ReportFilters] its report declares, in the
/// query, never over rows read into the phone.
abstract interface class ItemStockReportSource {
  /// Every stocked item with its stock and book value at the close of
  /// [asOf], narrowed by category, place and "in stock only". An archived
  /// item is listed only while something of it is still on the books.
  Future<List<StockLine>> stockLines(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Inventory in the books at the close of [asOf].
  Future<Money> inventoryAsOf(String firmId, BusinessDate asOf);

  /// Every item with stock or a movement in [period]: its opening, how it
  /// moved, and the value moved.
  Future<List<StockFlow>> stockFlows(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// The item [filters] names, day by day over [period]; null when it names
  /// none or there is no such item.
  Future<ItemHistory?> itemHistory(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every item on a posted bill, return or delivery in [period], with both
  /// sides of its trade.
  Future<List<ItemTrade>> itemTrade(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Each party who bought or sold the item [filters] names in [period];
  /// empty when it names none.
  Future<List<ItemPartyTrade>> itemParties(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// The items at or below their floor on [asOf], with what each sold over
  /// the [salesDays] up to it and who last supplied it.
  Future<List<LowStockLine>> lowStock(
    String firmId,
    BusinessDate asOf, {
    required int salesDays,
    ReportFilters filters = ReportFilters.none,
  });

  /// Every batch with something on the shelf, serial numbers apart.
  Future<List<BatchLine>> batches(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every serial number the shop has had, on the shelf or gone.
  Future<List<SerialLine>> serials(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every move of goods between places in [period], oldest first.
  Future<List<StockTransferLine>> stockTransfers(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every production run in [period], oldest first, with what it used.
  Future<List<ProductionRun>> productionRuns(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every stocked item with something on the shelf or a sale in the
  /// [salesDays] up to [asOf], with how it sold.
  Future<List<ItemSelling>> itemSelling(
    String firmId,
    BusinessDate asOf, {
    required int salesDays,
    ReportFilters filters = ReportFilters.none,
  });

  /// Every item with something on the shelf at the close of [asOf], its
  /// quantity split by how long ago it came in.
  Future<List<ItemAgeing>> stockAgeing(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  });
}
