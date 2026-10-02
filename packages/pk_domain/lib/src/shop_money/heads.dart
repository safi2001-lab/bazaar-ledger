/// The heads money goes out and comes in under (M47).
///
/// ## Expense heads are accounts
///
/// The profit and loss splits spending into direct costs (above the gross
/// profit line: freight on goods coming in, wastage) and indirect ones
/// (below it: rent, wages, bijli) by `accounts.is_direct`. A head of expense
/// therefore has to be an account, or there is nothing for that split to
/// read. The shipped heads are the chart's own (rent, salaries, utilities,
/// freight, misc); a head the shop adds is an expense account with no
/// system key, numbered after the last expense account as every account the
/// shop adds is (M26), and filed under Direct or Indirect Expenses.
///
/// Renaming one renames the account, everywhere it is read. Marking it
/// direct or indirect moves it across the gross profit line for every
/// period, past ones included, because the profit and loss reads the flag
/// as it is today; that is what the shopkeeper means by "freight is a cost
/// of the goods". Hiding one only stops it being offered on the expense
/// screen: its history stays where it is, in every report and in the
/// chart, which is why hiding is a note kept beside the chart rather than
/// `accounts.is_active`, which takes an account off the chart altogether.
///
/// ## Income heads are names on one account
///
/// The profit and loss puts under Other Income exactly one account, the
/// chart's `other_income` (4900); every other income account it files under
/// Sales. An income head made as an account of its own would therefore
/// swell the shop's gross profit with rent from a sub-let. So the shop's
/// other income all goes to 4900, where it is shown below gross profit as
/// it must be, and the head is the `income:<key>` tag on its lines. The
/// shipped heads are named here; the shop's own are kept in `settings`.
library;

import '../accounting/chart_of_accounts.dart';
import '../receivables/expense_builder.dart';

/// Why a head could not be added, renamed or changed, in words.
final class HeadRefused implements Exception {
  const HeadRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// One head an expense can go under: an account of the chart.
final class ExpenseHead {
  const ExpenseHead({
    required this.accountId,
    required this.code,
    required this.name,
    required this.isDirect,
    this.systemKey,
    this.hidden = false,
  });

  final String accountId;
  final String code;

  /// The account's name as the chart holds it.
  final String name;
  final String? systemKey;
  final bool isDirect;

  /// Not offered on the expense screen. Its history is untouched.
  final bool hidden;

  /// What an [ExpenseDraft] names it by: the shipped key, or `#<id>`.
  String get key => systemKey != null && expenseHeads.contains(systemKey)
      ? systemKey!
      : '#$accountId';

  /// One the app shipped with, which the screen names in the shopkeeper's
  /// language until the shop gives it a name of its own.
  bool get isShipped => systemKey != null && expenseHeads.contains(systemKey);

  /// Whether the shop renamed a shipped head. The chart is seeded with the
  /// English names; anything else is a name the shop chose.
  bool get isRenamed => isShipped && name != shippedAccountName(systemKey!);
}

/// The English name the chart seeds the account with [systemKey] under, or
/// null when the shipped chart has no such account.
String? shippedAccountName(String systemKey) {
  for (final spec in defaultChartOfAccounts) {
    if (spec.systemKey == systemKey) return spec.nameEn;
  }
  return null;
}

/// The settings row that keeps whether the expense head [accountId] is
/// hidden from the expense screen.
String expenseHeadSettingKey(String accountId) => 'expense.head.$accountId';

/// The heads of other income the app ships with, by key.
///
/// The ones a Pakistani shop meets: rent from the room upstairs or the
/// counter sub-let at the front, commission on a mobile load or a courier
/// parcel, profit on a bank account, the kabari's money for empty cartons
/// and sacks, money refunded, and anything else.
const shippedIncomeHeads = <String>[
  'rent_received',
  'commission',
  'interest',
  'scrap',
  'refund',
  'other',
];

/// The English name of a shipped income head, for the books and exports.
/// The screen names it in the shopkeeper's language.
String shippedIncomeHeadName(String key) => switch (key) {
  'rent_received' => 'Rent received',
  'commission' => 'Commission',
  'interest' => 'Bank profit and interest',
  'scrap' => 'Scrap and empties sold',
  'refund' => 'Refund received',
  'other' => 'Other income',
  _ => key,
};

/// The settings row an income head is kept in: a shipped one renamed or
/// hidden, or one of the shop's own.
String incomeHeadSettingKey(String key) => 'income.head.$key';

/// One head other income can come under.
final class IncomeHead {
  const IncomeHead({required this.key, this.name, this.hidden = false});

  final String key;

  /// The name the shop gave it, or null for a shipped head it never renamed.
  final String? name;

  final bool hidden;

  bool get isShipped => shippedIncomeHeads.contains(key);

  /// The name the books use: the shop's, or the shipped English one.
  String get bookName => name ?? shippedIncomeHeadName(key);
}

/// Whether [key] can name an income head: lower-case letters, digits and
/// underscores, as the shipped ones and the ids the app makes are. It is
/// written into a tag, so nothing else may get into it.
bool isIncomeHeadKey(String key) => RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(key);
