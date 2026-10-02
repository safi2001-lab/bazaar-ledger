import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// What one party bought from the shop and sold to it in a period, net of
/// what came back either way (M33). A walk-in is a party with no id.
final class PartyTrade {
  const PartyTrade({
    required this.name,
    required this.sales,
    required this.saleReturns,
    required this.purchases,
    required this.purchaseReturns,
    required this.salesTaxable,
    required this.returnsTaxable,
    required this.cost,
    required this.returnedCost,
    this.partyId,
    this.group,
  });

  /// Null for the walk-in customers, who are one row between them.
  final String? partyId;
  final String name;

  /// `parties.party_group`, or null when it has none.
  final String? group;

  /// Bills and returns as handed over, tax included.
  final Money sales;
  final Money saleReturns;
  final Money purchases;
  final Money purchaseReturns;

  /// Before tax, after every discount: what profit is reckoned on.
  final Money salesTaxable;
  final Money returnsTaxable;

  /// What the goods sold cost when they left the shelf, and what the goods
  /// returned cost when they came back.
  final Money cost;
  final Money returnedCost;

  Money get netSales => sales - saleReturns;
  Money get netPurchases => purchases - purchaseReturns;
  Money get netSalesTaxable => salesTaxable - returnsTaxable;
  Money get netCost => cost - returnedCost;
  Money get profit => netSalesTaxable - netCost;
}

/// One party as the khata stands today (M33).
final class PartyBalanceRow {
  const PartyBalanceRow({
    required this.partyId,
    required this.name,
    required this.partyType,
    required this.receivable,
    required this.payable,
    this.phone,
    this.group,
    this.creditLimit,
  });

  final String partyId;
  final String name;

  /// `customer`, `supplier` or `both`.
  final String partyType;
  final String? phone;
  final String? group;

  /// The khata's own balance: what they owe the shop, less any advance.
  final Money receivable;

  /// What the shop owes them.
  final Money payable;
  final Money? creditLimit;

  bool get hasBalance => !receivable.isZero || !payable.isZero;
}

/// One item a party bought or sold, over a period, net of returns (M33).
final class PartyItemTrade {
  const PartyItemTrade({
    required this.itemName,
    required this.unitCode,
    required this.qtySold,
    required this.saleAmount,
    required this.qtyPurchased,
    required this.purchaseAmount,
  });

  final String itemName;

  /// The base unit the quantities are counted in.
  final String unitCode;

  /// To the party, net of what they brought back.
  final Qty qtySold;

  /// Before tax, after every discount.
  final Money saleAmount;

  /// From the party, net of what went back to them.
  final Qty qtyPurchased;
  final Money purchaseAmount;
}

/// Both sides of one party's account, as the khata reads them (M33).
final class PartyLedgers {
  const PartyLedgers({
    required this.name,
    required this.partyType,
    required this.receivable,
    required this.payable,
  });

  final String name;

  /// `customer`, `supplier` or `both`.
  final String partyType;

  /// What they owe the shop, oldest first, with the balance after each:
  /// opening, bills, charges, payments, bounced cheques and returns.
  final List<LedgerEntry> receivable;

  /// What the shop owes them, the same way: deliveries, expenses left on
  /// account, goods sent back and payments made.
  final List<LedgerEntry> payable;
}

/// Where the party reports read from (M33).
abstract interface class PartyReportSource {
  /// Each party with a sale, a purchase or a return in [period], and the
  /// walk-in customers as one, narrowed by [filters] in the query.
  Future<List<PartyTrade>> partyTrade(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every party on the books, with the khata's balance each way today.
  Future<List<PartyBalanceRow>> partyBalances(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Each item bought or sold in [period], by the party [filters] names,
  /// or by everybody when it names none.
  Future<List<PartyItemTrade>> partyItems(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// One party's ledgers, both sides, from the start of the books; null
  /// when there is no such party.
  Future<PartyLedgers?> partyLedgers(String firmId, String partyId);
}
