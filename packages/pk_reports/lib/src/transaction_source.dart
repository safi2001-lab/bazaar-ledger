import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// One bill, for the sale and purchase reports and bill-wise profit (M33).
///
/// Every figure is the bill's own stored one, which is what was printed and
/// handed over: a report that recomputed a bill from its lines would be a
/// second answer to a question the bill already answered.
final class BillRow {
  const BillRow({
    required this.documentId,
    required this.date,
    required this.docNo,
    required this.docType,
    required this.party,
    required this.taxable,
    required this.tax,
    required this.total,
    required this.paid,
    required this.balance,
    required this.cost,
    this.partyId,
    this.modes = const [],
    this.enteredBy,
  });

  final String documentId;
  final BusinessDate date;
  final String docNo;

  /// `sale_invoice`, `sale_return`, `purchase_bill` or `purchase_return`.
  final String docType;
  final String? partyId;

  /// The name on the bill, or empty for a walk-in.
  final String party;

  /// Before tax, after every discount.
  final Money taxable;

  /// Sales tax and further tax.
  final Money tax;
  final Money total;

  /// Paid against it so far, at the counter or since.
  final Money paid;

  /// Still owed on it. A return against the bill has already come off.
  final Money balance;

  /// What the goods cost when they left the shelf, as the bill recorded it.
  final Money cost;

  /// How it was paid, `payments.mode`, each once: `cash`, `jazzcash`...
  final List<String> modes;

  /// Who entered it.
  final String? enteredBy;

  bool get isReturn =>
      docType == TransactionType.saleReturn ||
      docType == TransactionType.purchaseReturn;

  /// Paid, partly paid or not paid, from what is left on it.
  PaymentStatus get status {
    if (!balance.isPositive) return PaymentStatus.paid;
    return paid.isPositive ? PaymentStatus.partial : PaymentStatus.unpaid;
  }

  /// What the bill made over what its goods cost: the same figure
  /// `SaleCalculation.grossProfit` printed for it.
  Money get profit => taxable - cost;
}

/// One document or payment, for All Transactions (M33).
final class TransactionRow {
  const TransactionRow({
    required this.id,
    required this.date,
    required this.number,
    required this.type,
    required this.party,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    this.partyId,
    this.forHome = false,
  });

  final String id;
  final BusinessDate date;

  /// The document or payment number the shop wrote on the paper.
  final String number;

  /// An expense of the home's (M47): its debit is the owner's drawings, in
  /// money or in goods off the shelf. Read by the report as what it is
  /// rather than as the shop's expense (M58).
  final bool forHome;

  /// One of [TransactionType.all].
  final String type;
  final String? partyId;
  final String party;
  final Money total;
  final Money paid;
  final Money balance;

  /// A document's `posted` or `void`; a payment's `cleared`, `pending`,
  /// `bounced` or `void`.
  final String status;

  bool get isVoid => status == 'void';
  bool get isPayment => TransactionType.isPayment(type);
}

/// Money into or out of the drawer, the bank or a wallet, by what moved it,
/// over a period (M33).
final class MoneyFlow {
  const MoneyFlow({
    required this.kind,
    required this.inCash,
    required this.moneyIn,
    required this.moneyOut,
  });

  /// What moved it: the journal's `source_type`, `sale`, `payment`,
  /// `expense`, `reversal` and so on.
  final String kind;

  /// The drawer, rather than a bank account or a wallet.
  final bool inCash;
  final Money moneyIn;
  final Money moneyOut;
}

/// What was in the drawer, and in the bank and wallets, at one moment.
final class MoneyBalance {
  const MoneyBalance({required this.cash, required this.bank});

  static const zero = MoneyBalance(cash: Money.zero, bank: Money.zero);

  final Money cash;

  /// Bank accounts and mobile wallets together. Cheques in hand are not
  /// here: a cheque is not money until it clears.
  final Money bank;

  Money get total => cash + bank;
}

/// The stock figures a trading account reads: the Inventory account before
/// and after a period, and what came in from suppliers and went back to
/// them in it (M33).
final class StockFigures {
  const StockFigures({
    required this.opening,
    required this.purchases,
    required this.purchaseReturns,
    required this.closing,
  });

  /// Inventory in the books at the start of the period.
  final Money opening;

  /// What deliveries put onto the shelf, at cost.
  final Money purchases;

  /// What went back to suppliers, at cost.
  final Money purchaseReturns;

  /// Inventory in the books at the end of the period.
  final Money closing;
}

/// Where the transaction reports read from (M33).
abstract interface class TransactionReportSource {
  /// Every posted document of [docTypes] in [period], in date order,
  /// narrowed by [filters] in the query.
  Future<List<BillRow>> bills(
    String firmId,
    ReportPeriod period, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  });

  /// Every document and every payment taken or made on its own in
  /// [period], voids included, in the order they were recorded.
  Future<List<TransactionRow>> transactions(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every posting to the drawer, a bank account or a wallet in [period],
  /// summed by what moved it.
  Future<List<MoneyFlow>> moneyFlows(String firmId, ReportPeriod period);

  /// The drawer and the bank at the start of [day].
  Future<MoneyBalance> moneyBefore(String firmId, BusinessDate day);

  /// Inventory before and after [period], and the deliveries in it.
  Future<StockFigures> stockFigures(String firmId, ReportPeriod period);
}
