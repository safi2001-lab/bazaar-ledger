import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';

/// Reads for the bills that come round (M63). Each watches the refresh tick,
/// so a bill made, a template changed or the app brought back to the front
/// shows at once.

/// Every repeating bill, ended ones too. Empty for a role that may not sell.
final recurringBillsProvider = FutureProvider.autoDispose<List<RecurringBill>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  if (!services.recurring.mayUse || !services.isSetUp) return const [];
  return services.recurring.all();
});

/// What the home screen says: the bills due, and how many are kept and when
/// the next falls when none is.
final recurringHomeProvider =
    FutureProvider.autoDispose<
      ({List<RecurringDue> due, int kept, BusinessDate? next})
    >((ref) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      if (!services.recurring.mayUse || !services.isSetUp) {
        return (due: const <RecurringDue>[], kept: 0, next: null);
      }
      final recurring = services.recurring;
      final all = await recurring.all();
      final today = recurring.today;
      final live = [
        for (final b in all)
          if (!b.paused && !b.isOver(today)) b,
      ];
      BusinessDate? next;
      for (final b in live) {
        final on = b.nextAfter(today);
        if (on != null &&
            (next == null || on.value.compareTo(next.value) < 0)) {
          next = on;
        }
      }
      return (due: await recurring.due(), kept: live.length, next: next);
    });

/// One repeating bill as it is kept now.
final recurringBillProvider = FutureProvider.autoDispose
    .family<RecurringBill?, String>((ref, id) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).recurring.byId(id);
    });

/// The bills one template made, newest first.
final recurringHistoryProvider = FutureProvider.autoDispose
    .family<List<RecurringMade>, String>((ref, id) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).recurring.history(id);
    });

/// The names of a template's items that are no longer kept.
final recurringGoneProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, id) async {
      ref.watch(refreshTickProvider);
      final recurring = ref.watch(appServicesProvider).recurring;
      final bill = await recurring.byId(id);
      return bill == null ? const [] : recurring.goneItems(bill);
    });

/// A customer's repeating bills.
final recurringForPartyProvider = FutureProvider.autoDispose
    .family<List<RecurringBill>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      if (!services.recurring.mayUse) return const [];
      return services.recurring.forParty(partyId);
    });

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

/// The weekday [day] (1 Monday to 7 Sunday), as the shop says it.
String weekdayName(AppStrings s, int day) => switch (day) {
  1 => s.recurringMon,
  2 => s.recurringTue,
  3 => s.recurringWed,
  4 => s.recurringThu,
  5 => s.recurringFri,
  6 => s.recurringSat,
  _ => s.recurringSun,
};

/// "Roz", "Har Peer", "Har mahine ki 1 tareekh", "Har 3 din baad".
String everyText(AppStrings s, RepeatEvery every) => switch (every.kind) {
  RepeatKind.daily => s.recurringDaily,
  RepeatKind.weekly => s.recurringEveryWeekday(weekdayName(s, every.day)),
  RepeatKind.monthly => s.recurringEveryMonthDate(every.day),
  RepeatKind.everyDays => s.recurringEveryNDays(every.days),
};

/// A refusal in the shopkeeper's words: a repeating bill's own, a
/// permission's reason, or the error as it came.
String recurringProblemText(AppStrings s, Object error) {
  if (error is RecurringRefused) {
    final names = error.names.join(', ');
    return switch (error.problem) {
      RecurringProblem.noCustomer => s.recurringNoCustomer,
      RecurringProblem.noLines => s.recurringNoLines,
      RecurringProblem.badQty => s.recurringBadQty(names),
      RecurringProblem.badEvery => s.recurringBadEvery,
      RecurringProblem.endBeforeStart => s.recurringEndBeforeStart,
      RecurringProblem.badTimes => s.recurringBadTimes,
      RecurringProblem.itemGone => s.recurringProblemGone(names),
      RecurringProblem.serialItem => s.recurringProblemSerial(names),
      RecurringProblem.unitGone => s.recurringProblemUnit(names),
      RecurringProblem.customerGone => s.recurringProblemCustomerGone,
      RecurringProblem.alreadyMade =>
        error.docNo == null
            ? s.recurringProblemAlreadyMadePlain
            : s.recurringProblemAlreadyMade(error.docNo!),
      RecurringProblem.notKept => s.recurringProblemNotKept,
    };
  }
  if (error is PermissionDenied) return error.reason;
  return '$error';
}

/// What a bill copied onto a template left behind, in the counter's words
/// (M36's), and null when nothing was.
String? recurringLeftOutText(
  AppStrings s,
  List<({String name, RecurringLeftOut why})> leftOut,
) {
  if (leftOut.isEmpty) return null;
  return s.copyLeftOut(
    [
      for (final l in leftOut)
        switch (l.why) {
          RecurringLeftOut.free => s.copyWhyFree(l.name),
          RecurringLeftOut.serial => s.recurringWhySerial(l.name),
          RecurringLeftOut.gone => s.copyWhyGone(l.name),
          RecurringLeftOut.twice => s.copyWhyTwice(l.name),
        },
    ].join(', '),
  );
}
