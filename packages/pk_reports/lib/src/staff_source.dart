import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// Who the staff reports are grouped by (M35).
enum StaffGrouping {
  /// Whoever entered each bill: `documents.created_by`.
  user,

  /// The phone or till it was rung on: `documents.origin_device_id`, the
  /// counter whose letter is on the bill's number since M13.
  device,
}

/// What one member of staff, or one counter, rang up over a period (M35).
///
/// Every bill carries who made it and where, so this is a sum the books
/// already hold rather than a log anyone had to remember to keep.
final class StaffSales {
  const StaffSales({
    required this.id,
    required this.name,
    required this.bills,
    required this.sales,
    required this.salesBeforeDiscount,
    required this.discount,
    required this.discountedBills,
    required this.returns,
    required this.returnsValue,
    required this.voids,
    required this.voidsValue,
    this.detail,
  });

  /// The user or the device.
  final String id;
  final String name;

  /// A user's role, or a counter's letter.
  final String? detail;

  /// Sale bills that stand.
  final int bills;

  /// What they came to, tax included.
  final Money sales;

  /// What they came to before any discount, tax excluded.
  final Money salesBeforeDiscount;

  /// Line and bill discounts given on them.
  final Money discount;
  final int discountedBills;

  /// Sale returns they took, and what the returns gave back.
  final int returns;
  final Money returnsValue;

  /// Their sale bills that were later voided, and what those came to.
  final int voids;
  final Money voidsValue;
}

/// What came in by one payment mode over a period (M35). Each tender of a
/// split bill is its own payment, so a bill paid part in cash and part by
/// JazzCash is in both lines, each for its own part.
final class TenderTotal {
  const TenderTotal({
    required this.mode,
    required this.counterCount,
    required this.counter,
    required this.khataCount,
    required this.khata,
  });

  /// `payments.mode`: `cash`, `jazzcash`, `cheque`...
  final String mode;

  /// Tenders taken with a bill at the counter.
  final int counterCount;
  final Money counter;

  /// Money received on khatas, against bills or as an advance.
  final int khataCount;
  final Money khata;

  Money get total => counter + khata;
}

/// What a period's sale bills left owing when they were rung up (M35): the
/// udhaar given, which is not money until it is paid.
final class UdhaarGiven {
  const UdhaarGiven({required this.bills, required this.amount});

  static const none = UdhaarGiven(bills: 0, amount: Money.zero);

  /// Bills not paid in full at the counter.
  final int bills;
  final Money amount;
}

/// Selling in one hour of the shop's day, over a period (M35).
final class HourSales {
  const HourSales({
    required this.hour,
    required this.bills,
    required this.sales,
  });

  /// 0 to 23, Pakistan time.
  final int hour;
  final int bills;
  final Money sales;
}

/// One drawer count at a day close (M9), for the Z report (M35).
final class DrawerCount {
  const DrawerCount({
    required this.time,
    required this.expected,
    required this.counted,
    required this.closedBy,
  });

  /// `21:40`, Pakistan time.
  final String time;
  final Money expected;
  final Money counted;
  final String closedBy;

  /// Short (positive) or over (negative).
  Money get shortBy => expected - counted;
}

/// Everything a day's Z report reads, summed by SQLite (M35).
final class DayFigures {
  const DayFigures({
    required this.bills,
    required this.sales,
    required this.returns,
    required this.returnsValue,
    required this.discount,
    required this.linesSold,
    required this.salesTaxable,
    required this.salesCost,
    required this.returnsTaxable,
    required this.returnsCost,
    required this.expenses,
    required this.expensesValue,
    required this.tenders,
    required this.udhaar,
    required this.counts,
    this.takenHome = 0,
    this.takenHomeValue = Money.zero,
  });

  /// Ghar ka kharcha (M47): the home's spending and goods taken home, which
  /// are the owner's drawings and not among [expenses] since M58.
  final int takenHome;
  final Money takenHomeValue;

  /// Sale bills that stand, and what they came to.
  final int bills;
  final Money sales;

  /// Sale returns, and what they gave back.
  final int returns;
  final Money returnsValue;

  /// Line and bill discounts on the bills.
  final Money discount;

  /// Item lines on the bills: the things sold, one per line.
  final int linesSold;

  /// Before tax and after discount, and what the goods cost, for the gross
  /// profit; the same for what came back.
  final Money salesTaxable;
  final Money salesCost;
  final Money returnsTaxable;
  final Money returnsCost;

  /// The shop's expense vouchers, and what they came to; the home's are
  /// [takenHome].
  final int expenses;
  final Money expensesValue;

  /// What came in, by mode.
  final List<TenderTotal> tenders;

  /// What the bills left owing.
  final UdhaarGiven udhaar;

  /// The drawer counts at the day closes in the period, oldest first.
  final List<DrawerCount> counts;
}

/// One bill or entry put right after it was made (M35): a void, a return,
/// an edit (M31), a payment taken back.
final class ChangeRecord {
  const ChangeRecord({
    required this.date,
    required this.time,
    required this.action,
    required this.who,
    required this.summary,
    this.reference,
    this.party,
    this.amount,
    this.reason,
    this.documentId,
    this.docType,
    this.was,
    this.allowedBy,
  });

  /// What it came to before the change (M58): an edited payment, charge or
  /// expense's old amount, an opening balance's old figure. With [amount]
  /// beside it the change reads as a change, Rs 5,000 to Rs 500, as Marg's
  /// bill value changes do.
  final Money? was;

  /// Whose PIN let it through (M42, read here in M58): the owner who let it
  /// into closed books, or gave their PIN under Data Lock. Null when
  /// nobody's was asked for.
  final String? allowedBy;

  /// When it was done, Pakistan time.
  final BusinessDate date;
  final String time;

  /// The audit code: `DOCUMENT_VOIDED`, `SALE_RETURNED`, `EXPENSE_EDITED`...
  final String action;

  /// Who did it.
  final String who;

  /// The number of what was changed.
  final String? reference;
  final String? party;
  final Money? amount;

  /// Why, in the words the person who did it typed.
  final String? reason;

  /// The audit log's own line, for anything the columns do not say.
  final String summary;
  final String? documentId;
  final String? docType;
}

/// Where the staff and time reports read from (M35): sales by who and
/// where, how they were paid, the hours of the day, the night's Z report,
/// and what was changed after it was made.
abstract interface class StaffReportSource {
  /// Sales, discounts, returns and voids in [period], one row per user or
  /// per counter.
  Future<List<StaffSales>> staffSales(
    String firmId,
    ReportPeriod period, {
    required StaffGrouping by,
    ReportFilters filters = ReportFilters.none,
  });

  /// Money received in [period], by mode, at the counter and on khatas.
  /// A void payment and a bounced cheque are not money received.
  Future<List<TenderTotal>> tenders(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// What [period]'s sale bills left owing at the counter.
  Future<UdhaarGiven> udhaarGiven(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Sale bills in [period] by the hour of the day they were rung up.
  Future<List<HourSales>> hourlySales(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });

  /// The figures of a Z report for [period].
  Future<DayFigures> dayFigures(String firmId, ReportPeriod period);

  /// Voids, returns, edits and taken-back payments made in [period], in the
  /// order they were made.
  Future<List<ChangeRecord>> changes(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });
}
