/// What the expense and other-income screens read (M47).
library;

import 'package:pk_money/pk_money.dart';

/// One expense in the list, the shop's or the home's.
///
/// The head is read off the entry's debit line, as the M3 list always read
/// it, and named by the account: a head the shop added has no system key,
/// which the M3 row (`ExpenseRow.head`, required) could not carry.
final class ExpenseBookRow {
  const ExpenseBookRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.headKey,
    required this.headName,
    required this.amount,
    required this.owed,
    required this.note,
    this.headSystemKey,
    this.partyName,
    this.forHome = false,
    this.goods = false,
  });

  final String id;
  final String docNo;
  final String dateLocal;

  /// As an expense draft names the head: `rent`, or `#<id>` for the shop's
  /// own; `owner_drawings` for the home's.
  final String headKey;

  /// The account's name in the chart.
  final String headName;
  final String? headSystemKey;
  final Money amount;
  final Money owed;
  final String note;
  final String? partyName;

  /// Ghar ka kharcha: posted to Owner's Drawings.
  final bool forHome;

  /// Goods taken home off the shelf, rather than money.
  final bool goods;
}

/// What an expense's page needs beyond what M31's page reads: whose money
/// it was, the head by key and name, whether it was goods, and the tag it
/// carries, so a correction keeps paying the same monthly bill.
final class ExpenseFacts {
  const ExpenseFacts({
    required this.documentId,
    required this.headKey,
    required this.headName,
    this.headSystemKey,
    this.forHome = false,
    this.goods = false,
    this.tag,
  });

  final String documentId;
  final String headKey;
  final String headName;
  final String? headSystemKey;
  final bool forHome;
  final bool goods;
  final String? tag;
}

/// What the month's spending came to, the shop's and the home's apart.
final class MonthSplit {
  const MonthSplit({required this.shop, required this.home});

  final Money shop;
  final Money home;
}

/// One entry of the shop's other income.
final class OtherIncomeRow {
  const OtherIncomeRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.headKey,
    required this.amount,
    required this.note,
    this.fromName,
  });

  final String id;
  final String docNo;
  final String dateLocal;
  final String headKey;
  final Money amount;
  final String note;
  final String? fromName;
}

/// One entry of other income, whole, for its page.
final class OtherIncomeDetail {
  const OtherIncomeDetail({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.status,
    required this.headKey,
    required this.amount,
    required this.note,
    required this.enteredBy,
    this.fromName,
    this.paymentAccountId,
    this.voidReason,
  });

  final String id;
  final String docNo;
  final String dateLocal;

  /// `posted` or `void`.
  final String status;
  final String headKey;
  final Money amount;
  final String note;
  final String enteredBy;
  final String? fromName;

  /// The payment account it came into.
  final String? paymentAccountId;
  final String? voidReason;

  bool get isCancelled => status == 'void';
}
