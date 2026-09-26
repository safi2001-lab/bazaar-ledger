import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'journal_voucher.dart';

/// One account in the chart, with its balance now.
final class ChartAccount {
  const ChartAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.balance,
    this.systemKey,
  });

  final String id;
  final String code;
  final String name;

  /// `asset`, `liability`, `equity`, `income` or `expense`.
  final String type;
  final String? systemKey;

  /// Debit less credit. An asset or an expense is positive; a liability,
  /// equity or income account negative.
  final Money balance;

  /// The balance the way the account's own side reads it: what an asset
  /// holds, what a liability owes, what income earned.
  Money get onItsSide =>
      type == 'asset' || type == 'expense' ? balance : -balance;

  bool get isControl => controlAccountKeys.contains(systemKey);

  VoucherAccount get asVoucherAccount =>
      VoucherAccount(id: id, code: code, name: name, systemKey: systemKey);
}

/// One posting to an account, with the balance after it.
final class AccountLedgerLine {
  const AccountLedgerLine({
    required this.date,
    required this.entryNo,
    required this.narration,
    required this.debit,
    required this.credit,
    required this.balanceAfter,
  });

  final BusinessDate date;
  final String entryNo;
  final String narration;
  final Money debit;
  final Money credit;

  /// Debit less credit, running.
  final Money balanceAfter;
}
