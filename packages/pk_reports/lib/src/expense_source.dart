import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';

/// One expense voucher (M35): what was spent, on what, from where, by whom.
///
/// The head is the account its first journal line was debited to, read
/// back through the voucher's journal entry, never from a column of its own
/// (see `expense_builder.dart`): the voucher and the books cannot disagree
/// about where the money went.
final class ExpenseVoucher {
  const ExpenseVoucher({
    required this.documentId,
    required this.date,
    required this.docNo,
    required this.headId,
    required this.head,
    required this.isDirect,
    required this.paidFrom,
    required this.amount,
    required this.balance,
    required this.note,
    this.party,
    this.enteredBy,
    this.forHome = false,
    this.goods = false,
  });

  /// Ghar ka kharcha (M47): the voucher debits the owner's drawings, not an
  /// expense head. It is the owner taking his share of the shop, and the
  /// expense reports keep it apart from what the shop spent (M58).
  final bool forHome;

  /// Goods taken home off the shelf at cost, rather than money (M47).
  final bool goods;

  final String documentId;
  final BusinessDate date;
  final String docNo;

  /// Whoever it was paid to or is owed to, when the voucher names them.
  final String? party;

  /// The expense account, `accounts.id`, and its name: Rent, Bijli...
  final String headId;
  final String head;

  /// A direct expense (freight in, production) rather than an overhead.
  final bool isDirect;

  /// The account the money came out of, or "On account" when it is owed.
  final String paidFrom;
  final Money amount;

  /// Still owed on it.
  final Money balance;

  /// What it was for, in the shopkeeper's words. Every voucher has one.
  final String note;
  final String? enteredBy;
}

/// Where the expense reports read from (M35).
abstract interface class ExpenseReportSource {
  /// Every expense voucher that stands in [period], in date order, narrowed
  /// by head, who entered it, and the mode it was paid by. The home's are
  /// among them, marked [ExpenseVoucher.forHome], for the builders to keep
  /// apart (M58).
  Future<List<ExpenseVoucher>> expenseVouchers(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });
}
