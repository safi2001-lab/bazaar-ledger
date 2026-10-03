/// Selling a phone on qist (M50).
///
/// "Das hazaar abhi, baqi paanch hazaar mahina, har mahine ki paanch
/// tareekh": a down payment now and the rest in monthly instalments, often
/// with somebody standing guarantor. Qist selling is how most phones above
/// the cheapest are sold in Pakistan's markets, and the app built around it
/// (Qist Bazaar) has a hundred thousand installs.
///
/// ## What the books see
///
/// An ordinary bill, and nothing else. The phone is sold on a sale bill at
/// its price; the markup, when the shop charges one for waiting, is a charge
/// on the same bill — printed as "Qist markup", in the bill's total, booked
/// as other income — so there is no interest hidden in the phone's price and
/// the customer reads the whole cost on the paper. The down payment is the
/// bill's tender. Everything else is the bill's balance, on the customer's
/// khata as any udhaar is, and every receipt the customer brings settles it
/// exactly as any receipt settles a bill.
///
/// ## What the plan adds
///
/// When each part of that balance falls due. The plan is the agreement —
/// how many instalments, of how much, on which day of the month, and who
/// stood guarantor — and its instalments are due dates on the khata (M38):
/// an instalment past its day is overdue on the chase list and on the home
/// screen's card, one due today is due today, and the rest are not yet due,
/// however long ago the bill was made.
///
/// ## What has been paid is read, never written
///
/// The bill's balance already says it: whatever of the amount financed is
/// no longer owed has been paid. The instalments are paid off oldest first
/// out of that ([settleOldestFirst]), so a receipt — at the counter, on the
/// recovery man's sheet (M55), anywhere — pays the oldest instalment first
/// without knowing there is a plan, and a receipt cancelled next week puts
/// that instalment back to owing without anyone touching the plan.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'imei.dart';

/// Who stands behind a customer on qist.
final class Guarantor {
  const Guarantor({required this.name, this.cnic, this.phone});

  final String name;

  /// As typed; kept as thirteen digits.
  final String? cnic;
  final String? phone;
}

/// What the counter asks when a phone goes on qist.
///
/// The down payment and the markup are the bill's own figures — its tender
/// and its charge — so they are not asked twice here.
final class QistPlanDraft {
  const QistPlanDraft({
    required this.count,
    required this.dueDay,
    required this.firstDue,
    this.guarantor,
  });

  /// How many monthly instalments: 1 to [maxInstalments].
  final int count;

  /// The day of the month each falls due.
  final int dueDay;

  /// When the first falls due; each after it a month later, on [dueDay].
  final BusinessDate firstDue;

  final Guarantor? guarantor;

  /// Five years of instalments. A plan longer than that is a loan, not a
  /// phone sold on qist.
  static const maxInstalments = 60;
}

/// One instalment: which, when, how much.
final class Instalment {
  const Instalment({
    required this.seq,
    required this.dueOn,
    required this.amount,
  });

  final int seq;
  final BusinessDate dueOn;
  final Money amount;
}

/// A plan as the sale writes it, worked out from the bill's own figures.
final class QistPosting {
  const QistPosting({
    required this.soldOn,
    required this.downPayment,
    required this.markup,
    required this.financed,
    required this.dueDay,
    required this.instalments,
    this.guarantor,
  });

  final BusinessDate soldOn;
  final Money downPayment;

  /// The bill's charge for selling on instalments; zero when none.
  final Money markup;

  /// The bill's balance when it was made: what the instalments add up to.
  final Money financed;
  final int dueDay;
  final List<Instalment> instalments;
  final Guarantor? guarantor;
}

/// Why a plan was refused, in words the counter can act on.
final class QistRefused implements Exception {
  const QistRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The first instalment's day when nobody says otherwise: [dueDay] of the
/// month after the sale. A phone sold on 3 October with the 5th as its day
/// pays first on 5 November, not two days later.
BusinessDate firstDueAfter(BusinessDate sold, int dueDay) =>
    addMonthsClamped(sold, 1, dueDay);

/// [financed] in [count] monthly instalments, the first on [firstDue] and
/// each after it a month later on [dueDay] (or the month's last day).
///
/// Whole rupees each, as a shop says them — "paanch hazaar mahina" — with
/// whatever does not divide evenly on the last: Rs 50,001 over ten is nine
/// of Rs 5,000 and one of Rs 5,001. Never a paisa more or less than
/// [financed] in all.
List<Instalment> scheduleInstalments({
  required Money financed,
  required int count,
  required BusinessDate firstDue,
  required int dueDay,
}) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'at least one instalment');
  }
  if (!financed.isPositive) {
    throw ArgumentError.value(financed.inPaisa, 'financed', 'nothing to pay');
  }
  final even = financed.inPaisa ~/ count;
  if (even < 1) {
    throw ArgumentError.value(
      count,
      'count',
      'more instalments than there are paisa to pay',
    );
  }
  // Whole rupees when there are rupees to be had; a balance smaller than a
  // rupee an instalment is split to the paisa rather than left on the last.
  final each = even >= 100 ? even ~/ 100 * 100 : even;
  final out = <Instalment>[];
  for (var i = 0; i < count; i++) {
    final last = i == count - 1;
    final amount = last ? financed.inPaisa - each * (count - 1) : each;
    out.add(
      Instalment(
        seq: i + 1,
        dueOn: i == 0 ? firstDue : addMonthsClamped(firstDue, i, dueDay),
        amount: Money.paisa(amount),
      ),
    );
  }
  return out;
}

/// The plan for a bill of [total], [paid] at the counter, with [markup] in
/// its charges, to [partyId] on [soldOn]; or a refusal in words.
///
/// Pure, and run by the sale's own builder, so a plan that does not add up
/// to its bill is refused beneath every screen.
QistPosting postQist(
  QistPlanDraft plan, {
  required String? partyId,
  required BusinessDate soldOn,
  required Money total,
  required Money paid,
  required Money markup,
}) {
  if (partyId == null) {
    throw const QistRefused(
      'A phone on qist is sold to a named customer: the instalments are '
      'their khata.',
    );
  }
  final financed = total - paid;
  if (!financed.isPositive) {
    throw const QistRefused(
      'The down payment covers the whole bill, so there is nothing left to '
      'pay in instalments.',
    );
  }
  if (plan.count < 1 || plan.count > QistPlanDraft.maxInstalments) {
    throw QistRefused(
      'A qist plan has between 1 and ${QistPlanDraft.maxInstalments} '
      'instalments; ${plan.count} were asked for.',
    );
  }
  if (plan.dueDay < 1 || plan.dueDay > 31) {
    throw QistRefused('${plan.dueDay} is not a day of the month.');
  }
  if (plan.firstDue.value.compareTo(soldOn.value) <= 0) {
    throw QistRefused(
      'The first instalment falls due after the sale; '
      '${plan.firstDue.value} is not after ${soldOn.value}. What is paid '
      'today is the down payment.',
    );
  }
  if (financed.inPaisa < plan.count) {
    throw QistRefused(
      'Rs ${financed.amountOnly} cannot be split into ${plan.count} '
      'instalments.',
    );
  }
  final guarantor = plan.guarantor;
  if (guarantor != null) {
    if (guarantor.name.trim().isEmpty) {
      throw const QistRefused('The guarantor has no name.');
    }
    final cnic = guarantor.cnic;
    if (cnic != null && cnic.trim().isNotEmpty && !cnicWellFormed(cnic)) {
      throw QistRefused(
        'The guarantor\'s CNIC "$cnic" is not 13 digits (12345-1234567-1).',
      );
    }
  }
  return QistPosting(
    soldOn: soldOn,
    downPayment: paid,
    markup: markup,
    financed: financed,
    dueDay: plan.dueDay,
    guarantor: guarantor,
    instalments: scheduleInstalments(
      financed: financed,
      count: plan.count,
      firstDue: plan.firstDue,
      dueDay: plan.dueDay,
    ),
  );
}

/// Where one instalment stands.
final class InstalmentStanding {
  const InstalmentStanding({
    required this.instalment,
    required this.paid,
    required this.dueOn,
  });

  final Instalment instalment;

  /// How much of it has been paid, oldest instalments first.
  final Money paid;

  /// When what is left of it is due: its own day, or the day the plan was
  /// closed early when that came first.
  final BusinessDate dueOn;

  Money get left => instalment.amount - paid;
  bool get isPaid => !left.isPositive;
  bool get isPartPaid => paid.isPositive && !isPaid;

  /// Days since it fell due on [today]: positive is late, zero is today,
  /// negative the days still to go.
  int daysLateOn(BusinessDate today) => DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(dueOn.year, dueOn.month, dueOn.day)).inDays;

  bool isOverdueOn(BusinessDate today) => !isPaid && daysLateOn(today) > 0;
  bool isDueTodayOn(BusinessDate today) => !isPaid && daysLateOn(today) == 0;
}

/// [instalments] with [paidSoFar] paid off them oldest first, and the day
/// each one's remainder is due ([closedOn] brings every remainder forward to
/// it).
List<InstalmentStanding> settleOldestFirst(
  List<Instalment> instalments,
  Money paidSoFar, {
  BusinessDate? closedOn,
}) {
  var left = paidSoFar.isNegative ? Money.zero : paidSoFar;
  final sorted = [...instalments]..sort((a, b) => a.seq.compareTo(b.seq));
  return [
    for (final i in sorted)
      () {
        final paid = left >= i.amount ? i.amount : left;
        left -= paid;
        final due =
            closedOn != null && closedOn.value.compareTo(i.dueOn.value) < 0
            ? closedOn
            : i.dueOn;
        return InstalmentStanding(instalment: i, paid: paid, dueOn: due);
      }(),
  ];
}

/// How a plan stands, in one word.
enum QistStanding {
  /// Instalments still to come, none late.
  running,

  /// At least one instalment past its day.
  overdue,

  /// Everything paid.
  paidOff,

  /// Closed early, with something still owed.
  closed,

  /// Its bill was cancelled.
  cancelled,
}

/// A phone sold on qist, as the plan's page, the khata and the report read
/// it.
final class QistPlan {
  const QistPlan({
    required this.id,
    required this.documentId,
    required this.docNo,
    required this.partyId,
    required this.partyName,
    required this.soldOn,
    required this.billTotal,
    required this.downPayment,
    required this.markup,
    required this.financed,
    required this.billBalance,
    required this.dueDay,
    required this.instalments,
    this.partyPhone,
    this.billCancelled = false,
    this.guarantor,
    this.closedOn,
    this.closeNote,
    this.goods = const [],
  });

  final String id;
  final String documentId;
  final String docNo;
  final String partyId;
  final String partyName;
  final String? partyPhone;
  final BusinessDate soldOn;
  final Money billTotal;
  final Money downPayment;
  final Money markup;
  final Money financed;

  /// What is still owed on the bill now.
  final Money billBalance;
  final bool billCancelled;
  final int dueDay;
  final List<Instalment> instalments;
  final Guarantor? guarantor;
  final BusinessDate? closedOn;
  final String? closeNote;

  /// What was sold: "Samsung A15 · IMEI 356938035643809".
  final List<String> goods;

  int get count => instalments.length;

  /// What of the amount financed has been paid: whatever of it the bill no
  /// longer owes.
  Money get paid {
    final p = financed - (billBalance.isNegative ? Money.zero : billBalance);
    if (p.isNegative) return Money.zero;
    return p > financed ? financed : p;
  }

  /// Still to pay on the plan.
  Money get left => financed - paid;

  List<InstalmentStanding> get standings =>
      settleOldestFirst(instalments, paid, closedOn: closedOn);

  /// Owed on instalments already past their day on [today].
  Money overdueOn(BusinessDate today) => billCancelled
      ? Money.zero
      : Money.sum([
          for (final s in standings)
            if (s.isOverdueOn(today)) s.left,
        ]);

  /// Owed on instalments falling due on [today].
  Money dueTodayOn(BusinessDate today) => billCancelled
      ? Money.zero
      : Money.sum([
          for (final s in standings)
            if (s.isDueTodayOn(today)) s.left,
        ]);

  /// The next instalment not yet fully paid, if any.
  InstalmentStanding? get nextOpen =>
      standings.where((s) => !s.isPaid).firstOrNull;

  int get paidCount => standings.where((s) => s.isPaid).length;

  QistStanding standingOn(BusinessDate today) {
    if (billCancelled) return QistStanding.cancelled;
    if (!left.isPositive) return QistStanding.paidOff;
    if (overdueOn(today).isPositive) return QistStanding.overdue;
    if (closedOn != null) return QistStanding.closed;
    return QistStanding.running;
  }
}
