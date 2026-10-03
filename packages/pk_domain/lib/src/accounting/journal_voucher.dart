/// A journal voucher: an entry the accountant writes by hand.
///
/// The owner puts Rs 2 lakh of their own into the shop's bank account; the
/// owner takes Rs 20,000 home for the household; a bank charges its fee; a
/// debt is written off. None of these is a sale, a purchase or a payment on
/// a khata, and each is two lines in the books, which the accountant types.
///
/// The accounts that have a book of their own beneath them are refused:
/// Receivables and Payables (the khatas), Inventory (the shelf), and the
/// cheque and challan accounts. A hand entry there moves the total without
/// moving the book under it, and the two then disagree for ever. Those are
/// moved from their own screens.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// The accounts only their own screens may post to.
const controlAccountKeys = {
  'accounts_receivable',
  'accounts_payable',
  'inventory',
  'cheques_in_hand',
  'cheques_issued',
  'customer_advances',
  'goods_on_challan',
  // M65: the staff book's, where every line says whose advance it is.
  'staff_advances',
};

/// Why a voucher cannot be posted, in words.
final class VoucherRefused implements Exception {
  const VoucherRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// An account a voucher line can name.
final class VoucherAccount {
  const VoucherAccount({
    required this.id,
    required this.code,
    required this.name,
    this.systemKey,
  });

  final String id;
  final String code;
  final String name;
  final String? systemKey;

  bool get isControl => controlAccountKeys.contains(systemKey);
}

/// One line as typed: an account and an amount on one side.
final class VoucherLine {
  const VoucherLine({
    required this.account,
    this.debit = Money.zero,
    this.credit = Money.zero,
  });

  final VoucherAccount account;
  final Money debit;
  final Money credit;
}

/// Builds the entry a voucher writes.
final class JournalVoucherBuilder {
  const JournalVoucherBuilder();

  JournalEntryPosting build({
    required ActorContext actor,
    required String narration,
    required List<VoucherLine> lines,
    required AllocatedNumber number,
  }) {
    final said = narration.trim();
    if (said.isEmpty) {
      throw const VoucherRefused(
        'A voucher has to say what it is for. An entry nobody can explain is '
        'the first thing an auditor asks about.',
      );
    }
    final used = [
      for (final l in lines)
        if (!l.debit.isZero || !l.credit.isZero) l,
    ];
    if (used.length < 2) {
      throw const VoucherRefused('A voucher needs at least two lines.');
    }
    for (final l in used) {
      if (l.debit.isNegative || l.credit.isNegative) {
        throw const VoucherRefused('An amount cannot be less than nothing.');
      }
      if (!l.debit.isZero && !l.credit.isZero) {
        throw VoucherRefused(
          '${l.account.name} is on both sides. Put it on one.',
        );
      }
      if (l.account.isControl) {
        throw VoucherRefused(
          '${l.account.name} has its own book, and is moved from its own '
          'screen: a khata, a purchase, the shelf or the cheque drawer.',
        );
      }
    }
    final debit = Money.sum([for (final l in used) l.debit]);
    final credit = Money.sum([for (final l in used) l.credit]);
    if (debit != credit) {
      throw VoucherRefused(
        'Debits come to ${debit.amountOnly} and credits to '
        '${credit.amountOnly}. They have to be equal.',
      );
    }
    return JournalEntryPosting(
      entryNo: number.formatted,
      entryDateUtcMillis: actor.epochMillis,
      entryDateLocal: actor.businessDate.value,
      fiscalYear: actor.businessDate.fiscalYear,
      sourceType: 'manual',
      totalDebit: debit,
      totalCredit: credit,
      narration: said,
      lines: [
        for (var i = 0; i < used.length; i++)
          JournalLinePosting(
            lineNo: i + 1,
            accountSystemKey: '#${used[i].account.id}',
            debit: used[i].debit,
            credit: used[i].credit,
            narration: said,
          ),
      ],
    );
  }
}
