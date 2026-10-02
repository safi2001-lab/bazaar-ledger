import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../l10n/app_strings.dart';

/// "Due 12 Oct", "Due today", "Overdue 9 days" — one bill's standing, the
/// way the khata and the chase list both say it (M38).
///
/// [daysOverdue] positive is late, zero is today, negative is still to come;
/// [dueDateLocal] is said only while it is still to come, because once a
/// bill is late the number of days is the thing a shopkeeper acts on.
String dueText(AppStrings s, String dueDateLocal, int daysOverdue) {
  if (daysOverdue > 0) return s.dueOverdue(daysOverdue);
  if (daysOverdue == 0) return s.dueToday;
  return s.dueOn(shortDate(dueDateLocal));
}

/// The chip for [dueText]: quiet while there is time, amber on the day, red
/// once late.
class DueChip extends StatelessWidget {
  const DueChip({
    super.key,
    required this.dueDateLocal,
    required this.daysOverdue,
  });

  DueChip.of(BillDue bill, {super.key})
    : dueDateLocal = bill.dueDateLocal,
      daysOverdue = bill.daysOverdue;

  final String dueDateLocal;
  final int daysOverdue;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return BlChip(
      dueText(s, dueDateLocal, daysOverdue),
      tone: daysOverdue > 30
          ? BlChipTone.bad
          : daysOverdue >= 0
          ? BlChipTone.warn
          : BlChipTone.neutral,
      icon: daysOverdue > 0 ? Icons.schedule : null,
    );
  }
}

/// A promise's standing, in words.
String promiseStandingText(AppStrings s, PromiseStanding standing) =>
    switch (standing) {
      PromiseStanding.pending => s.promisePending,
      PromiseStanding.dueToday => s.promiseDueToday,
      PromiseStanding.kept => s.promiseKept,
      PromiseStanding.broken => s.promiseBroken,
      PromiseStanding.replaced => s.promiseReplaced,
      PromiseStanding.withdrawn => s.promiseWithdrawnLabel,
    };

BlChipTone promiseTone(PromiseStanding standing) => switch (standing) {
  PromiseStanding.kept => BlChipTone.good,
  PromiseStanding.dueToday => BlChipTone.warn,
  PromiseStanding.broken => BlChipTone.bad,
  _ => BlChipTone.neutral,
};

/// "Rs 5,000 promised for 9 Oct", or "Promised for 9 Oct" with no amount.
String promiseText(AppStrings s, PaymentPromise promise) {
  final day = shortDate(promise.promisedFor);
  final amount = promise.amount;
  return amount == null
      ? s.promiseFor(day)
      : s.promiseForAmount(day, amount.amountOnly);
}
