/// The bills that come every month, remembered (M47).
///
/// Rent on the 1st, the LESCO bill around the 10th, the boy's wages on the
/// 30th. A shopkeeper knows them by heart and still forgets one in a busy
/// week, and then the month's profit is wrong by Rs 40,000 until somebody
/// notices. DigiKhata's expense book reminds; Vyapar does not.
///
/// A monthly bill is a template, never a posting. On its day, and every day
/// after it in that month until it is paid, the Expenses screen shows it as
/// due with a "Pay now" that opens the expense already filled in. Nothing is
/// ever posted on its own: bijli is a different amount every month, and the
/// money has to actually leave the drawer before the books say it did.
///
/// ## Kept where, and known paid how
///
/// One `settings` row per bill (`expense.recurring.<id>`, JSON), the shape
/// M48 keeps a loan's terms in. No schema change. An expense paid from a
/// due card carries `expense:recurring:<id>` on its lines (see `tags.dart`),
/// so "this month's rent is paid" is a standing expense document with that
/// tag dated this month — never a guess from a head and an amount. One that
/// is cancelled is due again, because it is no longer standing.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../receivables/expense_builder.dart';
import '../time/clock.dart';
import 'tags.dart';

/// Why a monthly bill could not be kept, in words.
final class MonthlyBillRefused implements Exception {
  const MonthlyBillRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The settings row the monthly bill [id] is kept in.
String monthlyBillSettingKey(String id) => 'expense.recurring.$id';

/// The prefix every monthly bill's settings row starts with.
const monthlyBillSettingPrefix = 'expense.recurring.';

/// A bill that comes every month.
final class MonthlyBill {
  const MonthlyBill({
    required this.id,
    required this.headKey,
    required this.amount,
    required this.note,
    required this.day,
    this.forHome = false,
    this.paymentAccountId,
    this.skippedMonth,
  });

  final String id;

  /// The head it goes under, as an [ExpenseDraft] names one. Ignored for
  /// the home's spending, which has none.
  final String headKey;

  /// What it usually comes to. Filled in, and changed on the day when the
  /// bill says otherwise.
  final Money amount;

  /// What it is: "Dukaan ka kiraya", "LESCO bill".
  final String note;

  /// The day of the month it falls due, 1 to 31. In a month too short for
  /// it, the last day of that month.
  final int day;

  /// Ghar ka kharcha: the children's school fees every month.
  final bool forHome;

  /// Where it is usually paid from. Null for the drawer the screen offers
  /// first.
  final String? paymentAccountId;

  /// A month (`2026-10`) the shopkeeper said not to remind about: paid some
  /// other way, or not owed this once.
  final String? skippedMonth;

  /// The tag an expense paid against this bill carries.
  String get tag => recurringTag(id);

  /// The day it falls due in [year] and [month].
  BusinessDate dueIn(int year, int month) {
    final last = DateTime.utc(year, month + 1, 0).day;
    final d = day > last ? last : day;
    return BusinessDate(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}',
    );
  }

  /// The expense it fills the expense screen with.
  ExpenseDraft draft({required String? paymentAccountId}) => ExpenseDraft(
    accountSystemKey: forHome ? ownerDrawingsKey : headKey,
    amount: amount,
    note: note,
    paymentAccountId: paymentAccountId,
    forHome: forHome,
    tag: tag,
  );

  MonthlyBill copyWith({String? skippedMonth}) => MonthlyBill(
    id: id,
    headKey: headKey,
    amount: amount,
    note: note,
    day: day,
    forHome: forHome,
    paymentAccountId: paymentAccountId,
    skippedMonth: skippedMonth ?? this.skippedMonth,
  );

  String toJson() => jsonEncode({
    'head': headKey,
    'amountPaisa': amount.inPaisa,
    'note': note,
    'day': day,
    'forHome': forHome,
    'paymentAccountId': ?paymentAccountId,
    'skippedMonth': ?skippedMonth,
  });

  /// Read back from its settings row, or null when the row is not a
  /// monthly bill this version can read.
  static MonthlyBill? fromJson(String id, String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final head = decoded['head'];
    final paisa = decoded['amountPaisa'];
    final note = decoded['note'];
    final day = decoded['day'];
    if (head is! String || paisa is! int || note is! String || day is! int) {
      return null;
    }
    final account = decoded['paymentAccountId'];
    final skipped = decoded['skippedMonth'];
    return MonthlyBill(
      id: id,
      headKey: head,
      amount: Money.paisa(paisa),
      note: note,
      day: day,
      forHome: decoded['forHome'] == true,
      paymentAccountId: account is String ? account : null,
      skippedMonth: skipped is String ? skipped : null,
    );
  }
}

/// Refuses a monthly bill nobody could pay from.
void checkMonthlyBill(MonthlyBill bill) {
  if (!bill.amount.isPositive) {
    throw const MonthlyBillRefused(
      'A monthly bill needs what it usually comes to. It can be changed on '
      'the day.',
    );
  }
  if (bill.day < 1 || bill.day > 31) {
    throw const MonthlyBillRefused('The day of the month is 1 to 31.');
  }
  if (bill.note.trim().isEmpty) {
    throw const MonthlyBillRefused(
      'Say what the bill is, so the reminder can say it.',
    );
  }
  if (!bill.forHome && !isExpenseHeadKey(bill.headKey)) {
    throw MonthlyBillRefused(
      '"${bill.headKey}" is not an expense head this shop keeps.',
    );
  }
}

/// The month [date] is in, as `2026-10`.
String monthOf(BusinessDate date) => date.value.substring(0, 7);

/// The first and last day of the month [date] is in.
(BusinessDate, BusinessDate) monthSpan(BusinessDate date) {
  final first = BusinessDate('${monthOf(date)}-01');
  final last = DateTime.utc(date.year, date.month + 1, 0).day;
  return (
    first,
    BusinessDate('${monthOf(date)}-${last.toString().padLeft(2, '0')}'),
  );
}

/// A monthly bill whose day has come this month and which is not paid.
final class DueBill {
  const DueBill({required this.bill, required this.dueOn});

  final MonthlyBill bill;
  final BusinessDate dueOn;
}

/// The bills due by [today] this month and not yet paid, earliest first.
///
/// [paidTags] are the tags of this month's standing expenses. A bill whose
/// day has not come is not due yet, however close; a bill skipped for this
/// month is not due again until the next.
List<DueBill> billsDue({
  required List<MonthlyBill> bills,
  required Set<String> paidTags,
  required BusinessDate today,
}) {
  final month = monthOf(today);
  final due =
      <DueBill>[
        for (final bill in bills)
          if (bill.skippedMonth != month && !paidTags.contains(bill.tag))
            if (bill.dueIn(today.year, today.month) case final on
                when on.value.compareTo(today.value) <= 0)
              DueBill(bill: bill, dueOn: on),
      ]..sort((a, b) {
        final byDay = a.dueOn.value.compareTo(b.dueOn.value);
        return byDay != 0 ? byDay : a.bill.note.compareTo(b.bill.note);
      });
  return due;
}
