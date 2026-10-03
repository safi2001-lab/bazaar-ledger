/// Loyalty points (M66): what each customer earned, used, let lapse and
/// holds — Vyapar's "Total Loyalty Points Rewarded" and "Total Discount
/// Redeemed", per customer and in all.
///
/// Kept here, out of `ReportEngine._build` and the other groups' files, so
/// the engine carries it as one case and the reports other milestones add
/// touch different lines. The points are worked out by the domain's own
/// rule (`loyaltyStanding`), the one the counter and the bill use, from the
/// books as they stand; this file only lays them out.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// One customer's bills, as loyalty counts them.
final class LoyaltyCustomer {
  const LoyaltyCustomer({
    required this.partyId,
    required this.name,
    this.phone,
    this.bills = const [],
  });

  final String partyId;
  final String name;
  final String? phone;
  final List<LoyaltyBill> bills;
}

/// Where the loyalty report reads from.
abstract interface class LoyaltyReportSource {
  /// The shop's rule, every version.
  Future<LoyaltyRules> loyaltyRules(String firmId);

  /// Every named customer with a sale bill, and those bills, narrowed by
  /// party and party group.
  Future<List<LoyaltyCustomer>> loyaltyCustomers(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  });
}

/// The reports this file builds.
const loyaltyReportKinds = {ReportKind.loyaltyPoints};

/// Builds [kind], one of [loyaltyReportKinds].
Future<ReportTable> buildLoyaltyReport(
  ReportKind kind, {
  required LoyaltyReportSource source,
  required String firmId,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.loyaltyPoints => loyaltyPointsReport(
    today,
    await source.loyaltyRules(firmId),
    await source.loyaltyCustomers(firmId, filters: filters),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M66 report'),
};

/// Loyalty points, as of [today]: per customer what they earned, used and
/// let lapse, and what they hold, most held first, with what it is worth at
/// today's rate.
ReportTable loyaltyPointsReport(
  BusinessDate today,
  LoyaltyRules rules,
  List<LoyaltyCustomer> customers,
) {
  final rule = rules.current;
  final rows =
      <({LoyaltyCustomer who, LoyaltyStanding standing})>[
        for (final c in customers)
          if (loyaltyStanding(rules, c.bills, today: today.value) case final s
              when s.earned != 0 || s.redeemed != 0 || s.expired != 0)
            (who: c, standing: s),
      ]..sort((a, b) {
        final byHeld = b.standing.outstanding.compareTo(a.standing.outstanding);
        return byHeld != 0 ? byHeld : a.who.name.compareTo(b.who.name);
      });

  Money worth(int points) => rule?.valueOf(points) ?? Money.zero;
  int sum(int Function(LoyaltyStanding s) f) =>
      rows.fold<int>(0, (total, r) => total + f(r.standing));
  final held = sum((s) => s.outstanding < 0 ? 0 : s.outstanding);
  final given = Money.sum([for (final r in rows) r.standing.redeemedValue]);

  return ReportTable(
    id: 'loyalty_points',
    title: 'Loyalty points',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Phone', CellKind.text),
      ReportColumn('Earned', CellKind.count),
      ReportColumn('Redeemed', CellKind.count),
      ReportColumn('Discount given', CellKind.money),
      ReportColumn('Expired', CellKind.count),
      ReportColumn('Outstanding', CellKind.count),
      ReportColumn('Worth today', CellKind.money),
      ReportColumn('Expiring next', CellKind.text),
    ],
    rows: [
      for (final r in rows)
        ReportRow([
          r.who.name,
          r.who.phone ?? '',
          r.standing.earned,
          r.standing.redeemed,
          r.standing.redeemedValue,
          r.standing.expired,
          r.standing.outstanding,
          worth(r.standing.outstanding < 0 ? 0 : r.standing.outstanding),
          switch (r.standing.expiringNext) {
            final next? => '${next.points} on ${next.on}',
            null => '',
          },
        ], link: ReportLink.party(r.who.partyId, label: r.who.name)),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 customer' : '${rows.length} customers',
        sum((s) => s.earned),
        sum((s) => s.redeemed),
        given,
        sum((s) => s.expired),
        held,
        worth(held),
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Points given', sum((s) => s.earned)),
      ReportFigure('Discount redeemed', given),
      ReportFigure.count('Points outstanding', held),
      ReportFigure('Outstanding at today\'s rate', worth(held)),
    ],
    notes: ['As of ${today.value}. $_earnedOnPaid', _aMemoNotALiability],
  );
}

const _earnedOnPaid =
    'Points are earned on what was paid against a bill, up to what the '
    'customer kept of it: a bill on udhaar earns as it is paid, a return '
    'takes its points back, and a cancelled bill earns nothing and gives '
    'back what it spent.';

const _aMemoNotALiability =
    'Points outstanding are a promise, not an entry in the books: a '
    'redemption is booked as a discount on the bill that uses the points, '
    'the day it is given.';
