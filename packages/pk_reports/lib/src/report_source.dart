import 'package:pk_domain/pk_domain.dart';

import 'period.dart';

/// What moved through one account in a period.
final class AccountMovement {
  const AccountMovement({
    required this.code,
    required this.name,
    required this.type,
    required this.debit,
    required this.credit,
    this.systemKey,
    this.isDirect = false,
  });

  final String code;
  final String name;

  /// `asset`, `liability`, `equity`, `income` or `expense`.
  final String type;
  final String? systemKey;
  final bool isDirect;
  final Money debit;
  final Money credit;

  /// Debit less credit: what an expense cost, or what an asset gained.
  Money get net => debit - credit;
}

/// One posting to the cash in the drawer.
final class CashMovement {
  const CashMovement({
    required this.date,
    required this.entryNo,
    required this.narration,
    required this.moneyIn,
    required this.moneyOut,
  });

  final BusinessDate date;
  final String entryNo;
  final String narration;
  final Money moneyIn;
  final Money moneyOut;
}

/// One journal entry, as the day book lists it.
final class DayBookEntry {
  const DayBookEntry({
    required this.date,
    required this.entryNo,
    required this.sourceType,
    required this.narration,
    required this.amount,
  });

  final BusinessDate date;
  final String entryNo;

  /// `sale`, `purchase`, `payment`, `expense`, `reversal` and so on.
  final String sourceType;
  final String narration;
  final Money amount;
}

/// What one item sold for in a period, net of what came back.
final class ItemSales {
  const ItemSales({
    required this.itemName,
    required this.unitCode,
    required this.qtySold,
    required this.qtyReturned,
    required this.salesValue,
    required this.returnsValue,
    required this.cost,
    required this.returnedCost,
  });

  final String itemName;

  /// The base unit the quantities are counted in.
  final String unitCode;
  final Qty qtySold;
  final Qty qtyReturned;

  /// Before tax, after every discount.
  final Money salesValue;
  final Money returnsValue;
  final Money cost;
  final Money returnedCost;

  Qty get netQty => qtySold - qtyReturned;
  Money get netSales => salesValue - returnsValue;
  Money get netCost => cost - returnedCost;
  Money get profit => netSales - netCost;
}

/// What is on the shelf of one item, and what it cost on average.
final class StockPosition {
  const StockPosition({
    required this.itemName,
    required this.unitCode,
    required this.qty,
    required this.averageCost,
  });

  final String itemName;
  final String unitCode;
  final Qty qty;
  final Rate averageCost;

  Money get value => averageCost.amountFor(qty);
}

/// One day's selling.
final class DaySales {
  const DaySales({
    required this.date,
    required this.bills,
    required this.sales,
    required this.returns,
    required this.received,
    required this.onUdhaar,
  });

  final BusinessDate date;
  final int bills;

  /// What the day's bills came to, tax included.
  final Money sales;

  /// What the day's sale returns gave back.
  final Money returns;

  /// What was paid at the counter against the day's bills.
  final Money received;

  /// What the day's bills left owing.
  final Money onUdhaar;
}

/// What one customer owes, by how long it has been owed.
final class PartyReceivable {
  const PartyReceivable({
    required this.name,
    required this.opening,
    required this.upTo30,
    required this.upTo60,
    required this.upTo90,
    required this.over90,
    required this.advance,
  });

  final String name;

  /// The balance brought forward when the khata was opened, undated.
  final Money opening;
  final Money upTo30;
  final Money upTo60;
  final Money upTo90;
  final Money over90;

  /// Money the shop is holding for them, which comes off what they owe.
  final Money advance;

  /// The same figure as the khata's balance.
  Money get owed => opening + upTo30 + upTo60 + upTo90 + over90 - advance;
}

/// Where the reports read from. Implemented against the database in
/// pk_data; every method is a read, and none of them adds anything up that a
/// builder then adds up again.
abstract interface class ReportSource {
  /// Every account with anything posted to it in [period].
  Future<List<AccountMovement>> accountMovements(
    String firmId,
    ReportPeriod period,
  );

  /// The cash in the drawer at the start of [day], from every posting before.
  Future<Money> cashBefore(String firmId, BusinessDate day);

  /// Every posting to cash in [period], in the order it was recorded.
  Future<List<CashMovement>> cashMovements(String firmId, ReportPeriod period);

  /// Every journal entry in [period], in the order it was recorded.
  Future<List<DayBookEntry>> dayBook(String firmId, ReportPeriod period);

  /// Sales and returns per item in [period].
  Future<List<ItemSales>> itemSales(String firmId, ReportPeriod period);

  /// Every stocked item that is not archived, with what is on the shelf now.
  Future<List<StockPosition>> stockPositions(String firmId);

  /// The balance of Inventory in the books now.
  Future<Money> inventoryInBooks(String firmId);

  /// Each day in [period] with a bill or a return on it.
  Future<List<DaySales>> dailySales(String firmId, ReportPeriod period);

  /// Every customer with anything open, aged on [asOf].
  Future<List<PartyReceivable>> receivables(String firmId, BusinessDate asOf);

  /// Every account with anything posted to it on or before [asOf], with
  /// everything posted to it since the books began.
  Future<List<AccountMovement>> accountBalances(
    String firmId,
    BusinessDate asOf,
  );

  /// Every supplier the shop owes, aged on [asOf].
  Future<List<PartyReceivable>> payables(String firmId, BusinessDate asOf);
}
