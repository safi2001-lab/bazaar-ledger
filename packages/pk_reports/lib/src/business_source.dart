import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// How long a customer has to pay a bill when their khata sets no credit
/// days of its own (M35): thirty, the first bucket every ageing in this
/// market's apps uses, and the month most wholesale udhaar is given for.
/// A khata's own `credit_days` always wins over it.
const defaultCreditDays = 30;

/// One money account's movements over a period, as a bank statement lists
/// them (M35): a bank account, a mobile wallet, or the drawer when it is
/// asked for by name.
final class BankStatementAccount {
  const BankStatementAccount({
    required this.accountId,
    required this.name,
    required this.kind,
    required this.opening,
    required this.lines,
  });

  /// The ledger account, `accounts.id`.
  final String accountId;
  final String name;

  /// `cash`, `bank` or `wallet`.
  final String kind;

  /// What the books held in it at the start of the period.
  final Money opening;

  /// Every movement in the period, in the order it was recorded.
  final List<BankLine> lines;
}

/// One movement into or out of a money account (M35).
final class BankLine {
  const BankLine({
    required this.date,
    required this.description,
    required this.deposit,
    required this.withdrawal,
    this.party,
    this.reference,
    this.documentId,
    this.docType,
  });

  final BusinessDate date;

  /// What the entry says it was: "Sale INV-0012", "Received from Rashid".
  final String description;

  /// The bill, receipt or entry number on the paper.
  final String? reference;
  final String? party;

  /// Into the account.
  final Money deposit;

  /// Out of it.
  final Money withdrawal;

  /// The document behind it, for opening it from the report.
  final String? documentId;
  final String? docType;
}

/// The discounts given to and taken from one party over a period (M35). A
/// walk-in is a party with no id, and the walk-ins are one row.
final class PartyDiscount {
  const PartyDiscount({
    required this.name,
    required this.saleBills,
    required this.salesBeforeDiscount,
    required this.discountGiven,
    required this.purchaseBills,
    required this.purchasesBeforeDiscount,
    required this.discountReceived,
    this.partyId,
  });

  final String? partyId;
  final String name;

  /// Sale bills that carried a discount.
  final int saleBills;

  /// What those bills came to before any discount.
  final Money salesBeforeDiscount;

  /// Line and bill discounts given on the party's sale bills.
  final Money discountGiven;

  /// Purchase bills that carried a discount.
  final int purchaseBills;
  final Money purchasesBeforeDiscount;

  /// Line and bill discounts the party gave the shop on its deliveries.
  final Money discountReceived;
}

/// How one customer pays (M35): of the bills in a period that went on
/// udhaar, how many are settled, how long they took, how many were late,
/// and how many are past due now.
final class PaymentRecord {
  const PaymentRecord({
    required this.partyId,
    required this.name,
    required this.creditDays,
    required this.udhaarBills,
    required this.settledBills,
    required this.daysToSettle,
    required this.paidLate,
    required this.overdueBills,
    required this.overdue,
    required this.open,
    this.phone,
  });

  final String partyId;
  final String name;
  final String? phone;

  /// The days the customer is given, their khata's own or
  /// [defaultCreditDays].
  final int creditDays;

  /// Bills in the period not paid in full at the counter.
  final int udhaarBills;

  /// Of those, the ones nothing is left on.
  final int settledBills;

  /// The days each settled bill took, from its date to the payment that
  /// cleared it, added together; the builder divides.
  final int daysToSettle;

  /// Settled bills that took longer than [creditDays].
  final int paidLate;

  /// Bills still open today that are past [creditDays].
  final int overdueBills;
  final Money overdue;

  /// Everything still open on the period's bills.
  final Money open;
}

/// A customer with udhaar past its due date, as of today (M35).
final class DefaulterRow {
  const DefaulterRow({
    required this.partyId,
    required this.name,
    required this.creditDays,
    required this.open,
    required this.overdue,
    required this.overdueBills,
    required this.oldestBill,
    this.phone,
    this.creditLimit,
    this.lastPayment,
  });

  final String partyId;
  final String name;
  final String? phone;
  final int creditDays;

  /// Everything still owed on bills and charges.
  final Money open;

  /// The part of [open] that is past its due date.
  final Money overdue;
  final int overdueBills;

  /// The date of the oldest bill still owed and past due.
  final BusinessDate oldestBill;
  final Money? creditLimit;

  /// When they last paid anything, if ever.
  final BusinessDate? lastPayment;
}

/// Where the business status reports read from (M35): the bank statement,
/// the discounts, and how customers pay.
abstract interface class BusinessReportSource {
  /// Each money account [filters] names, or every bank and wallet account
  /// when it names none, with its opening on the period's first day and
  /// every movement in the period.
  Future<List<BankStatementAccount>> bankStatements(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Each party with a discounted sale or purchase bill in [period], and
  /// the walk-ins as one.
  Future<List<PartyDiscount>> discountsByParty(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Each customer with a sale bill in [period] that went on udhaar, judged
  /// as of [today].
  Future<List<PaymentRecord>> paymentRecords(
    String firmId,
    ReportPeriod period,
    BusinessDate today, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every customer with a bill or charge past its due date on [today].
  Future<List<DefaulterRow>> defaulters(
    String firmId,
    BusinessDate today, {
    ReportFilters filters = ReportFilters.none,
  });
}
