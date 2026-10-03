import 'package:pk_domain/pk_domain.dart';

import 'business_source.dart';
import 'collections_reports.dart'; // M54
import 'expense_source.dart';
import 'filters.dart';
import 'item_stock_source.dart';
import 'loan_reports.dart';
import 'mobile_reports.dart'; // M50
import 'order_source.dart';
import 'party_source.dart';
import 'period.dart';
import 'pharmacy_reports.dart';
import 'staff_source.dart';
import 'tax_source.dart';
import 'transaction_source.dart';
import 'udhaar_reports.dart';

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
///
/// Since M33 it carries what the day book of every other shop app shows:
/// who it was with, the paper's own number, and the money that went into
/// or out of the drawer, the bank and the wallets with it.
final class DayBookEntry {
  const DayBookEntry({
    required this.date,
    required this.entryNo,
    required this.sourceType,
    required this.narration,
    required this.amount,
    this.reference,
    this.party,
    this.moneyIn = Money.zero,
    this.moneyOut = Money.zero,
    this.documentId,
    this.docType,
    this.tenders = const {},
  });

  final BusinessDate date;
  final String entryNo;

  /// `sale`, `purchase`, `payment`, `expense`, `reversal` and so on: the
  /// journal's `source_type`. Since M58 three are said more exactly, because
  /// the source type alone gives the wrong word: an `other_income` entry
  /// with no party behind it is the shop's own income,
  /// [TransactionType.otherIncome], not a charge on a khata; an `expense`
  /// debiting the owner's drawings is ghar ka kharcha,
  /// [TransactionType.ownerDrawings]; and a `manual` entry tagged to a loan
  /// (M48) is `loan`.
  final String sourceType;
  final String narration;

  /// What the transaction came to: the bill's total, or the payment's
  /// amount, or for an entry with neither, the entry's own size.
  final Money amount;

  /// The bill or payment number on the paper, when there is one.
  final String? reference;

  /// The customer or supplier, when there is one.
  final String? party;

  /// Into the drawer, a bank account or a wallet with this entry.
  final Money moneyIn;

  /// Out of them.
  final Money moneyOut;

  /// The document behind the entry, for opening it from the report.
  final String? documentId;
  final String? docType;

  /// The tenders taken with the bill at the counter, by `payments.mode`
  /// (M62), so a bill paid two ways says each with its amount beside the
  /// one figure of money in. Empty for anything else.
  final Map<String, Money> tenders;
}

/// What one item sold for in a period, net of what came back.
///
/// Since M58 the lines with no item behind them, khula maal sold by the
/// rupee (M37), are one of these too, [isLoose], named
/// `ItemTrade.looseLines` as M34's reports name them: their money is in the
/// sales, and a Sales by item that left them out came to less than the bills.
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
    this.itemId,
    this.isLoose = false,
  });

  final String itemName;

  /// The item, for opening its stock history; null for khula maal.
  final String? itemId;

  /// Every line with no item, together: no unit to count it in and no cost
  /// on record.
  final bool isLoose;

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

/// Tax charged or given back under one code in a period.
final class TaxLine {
  const TaxLine({
    required this.code,
    required this.kind,
    required this.rateBp,
    required this.base,
    required this.amount,
    required this.isReturn,
  });

  /// `ST_STD_18`, `ST_3RD_18`, `FURTHER_4`, `ST_RETURN`... and for the
  /// province's tax on a service `PRA_STD`, `PRA_CARD`, and what a return
  /// gave back of them, `PRA_CARD_RETURN` (M61).
  final String code;

  /// `sales_tax`, `further_tax`, or `provincial_st` (M61).
  final String kind;
  final int rateBp;
  final Money base;
  final Money amount;

  /// Given back on a return rather than charged on a sale.
  final bool isReturn;
}

/// One purchase bill, for the purchase register (M24).
final class PurchaseRegisterLine {
  const PurchaseRegisterLine({
    required this.date,
    required this.docNo,
    required this.supplier,
    required this.taxable,
    required this.tax,
    required this.total,
    required this.owed,
    this.supplierBillNo,
    this.supplierNtn,
    this.isReturn = false,
  });

  final BusinessDate date;
  final String docNo;
  final String supplier;
  final String? supplierBillNo;
  final String? supplierNtn;
  final Money taxable;
  final Money tax;
  final Money total;

  /// Still unpaid on it.
  final Money owed;

  /// Goods sent back: the register shows it against the purchases.
  final bool isReturn;
}

/// Where the reports read from. Implemented against the database in
/// pk_data; every method is a read, and none of them adds anything up that a
/// builder then adds up again.
///
/// Each group of reports added since M33 declares its reads in its own
/// interface, beside its own row types, and this one takes them all: a new
/// group is a new file and one more name on the `implements` line.
abstract interface class ReportSource
    implements
        TransactionReportSource,
        PartyReportSource,
        ItemStockReportSource,
        // M35
        BusinessReportSource,
        StaffReportSource,
        TaxReportSource,
        ExpenseReportSource,
        OrderReportSource,
        // M58
        LoanReportSource,
        UdhaarReportSource,
        // M49
        PharmacyReportSource,
        // M50
        MobileReportSource,
        // M54
        CollectionsReportSource {
  /// What a filter can be set to: the items, categories, party groups or
  /// staff the shop has, matching [query] (M33).
  Future<List<ReportChoice>> choices(
    String firmId,
    ReportFilter filter, {
    String query = '',
    int limit = 50,
  });

  /// Every account with anything posted to it in [period].
  Future<List<AccountMovement>> accountMovements(
    String firmId,
    ReportPeriod period,
  );

  /// The cash in the drawer at the start of [day], from every posting before.
  Future<Money> cashBefore(String firmId, BusinessDate day);

  /// Every posting to cash in [period], in the order it was recorded.
  Future<List<CashMovement>> cashMovements(String firmId, ReportPeriod period);

  /// Every journal entry in [period], in the order it was recorded, with the
  /// money it moved; narrowed to one person's entries by [filters].
  Future<List<DayBookEntry>> dayBook(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

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

  /// Tax on posted sales and returns in [period], by code.
  Future<List<TaxLine>> taxLines(String firmId, ReportPeriod period);

  /// Sales before any return, by calendar month, for [period].
  Future<Map<String, Money>> monthlyTurnover(
    String firmId,
    ReportPeriod period,
  );

  /// Every batch still on the shelf that has an expiry date.
  Future<List<LotOnHand>> batchesWithExpiry(String firmId);

  /// Every supplier the shop owes, aged on [asOf].
  Future<List<PartyReceivable>> payables(String firmId, BusinessDate asOf);

  /// Every posted purchase bill and purchase return in [period], in date
  /// order.
  Future<List<PurchaseRegisterLine>> purchaseRegister(
    String firmId,
    ReportPeriod period,
  );
}
