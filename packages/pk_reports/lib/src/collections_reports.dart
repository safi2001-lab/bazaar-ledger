/// What should come in over the next week (M54): the report M35 left
/// because bills had no day they fell due, built now that they have (M38)
/// and a phone on qist falls due instalment by instalment (M50).
///
/// Kept here, out of `ReportEngine._build` and the other groups' files, so
/// the engine carries it as one case and the reports other milestones add
/// touch different lines.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// How far ahead the report looks: today and the six days after it.
const expectedCollectionDays = 7;

/// What one customer should pay over the next [expectedCollectionDays].
final class ExpectedCollectionRow {
  const ExpectedCollectionRow({
    required this.partyId,
    required this.name,
    this.phone,
    this.fallsDue = Money.zero,
    this.firstDue,
    this.onQist = Money.zero,
    this.promised = Money.zero,
    this.promisedFor,
    this.late = Money.zero,
  });

  final String partyId;
  final String name;
  final String? phone;

  /// What their open bills — and, for a bill sold on qist, its instalments
  /// — fall due for from today to the last day of the week, by M38's due
  /// dates: each bill's date plus the customer's credit days.
  final Money fallsDue;

  /// The first of those days.
  final String? firstDue;

  /// Of [fallsDue], what is a qist instalment (M50).
  final Money onQist;

  /// What they promised to pay on a day in the week (M38), less what has
  /// come in since they promised it; a promise with no amount is counted
  /// at what they owe.
  final Money promised;

  /// The day they promised it for.
  final String? promisedFor;

  /// Already past its day before the week begins: not in [expected], said
  /// beside it, because it is the money a shopkeeper asks for first.
  final Money late;

  /// What to expect from them this week: the larger of what falls due and
  /// what they promised. Never the two added, because a promise is nearly
  /// always the customer's word about the very bills falling due.
  Money get expected => promised > fallsDue ? promised : fallsDue;
}

/// Where the expected-collections report reads from.
abstract interface class CollectionsReportSource {
  /// Every customer with something falling due or promised from [asOf] to
  /// [asOf] plus six days, narrowed by party and party group.
  Future<List<ExpectedCollectionRow>> expectedCollections(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  });
}

/// The reports this file builds.
const collectionsReportKinds = {ReportKind.expectedCollections};

/// Builds [kind], one of [collectionsReportKinds].
Future<ReportTable> buildCollectionsReport(
  ReportKind kind, {
  required CollectionsReportSource source,
  required String firmId,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.expectedCollections => expectedCollectionsReport(
    today,
    await source.expectedCollections(firmId, today, filters: filters),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M54 report'),
};

/// Expected collections, today and the next six days: per customer, what
/// falls due and what was promised, the earliest day first, with totals.
ReportTable expectedCollectionsReport(
  BusinessDate asOf,
  List<ExpectedCollectionRow> rows,
) {
  final last = asOf.addDays(expectedCollectionDays - 1);
  final listed = rows.where((r) => r.expected.isPositive).toList()
    ..sort((a, b) {
      final ad = _earliest(a), bd = _earliest(b);
      final byDay = ad.compareTo(bd);
      if (byDay != 0) return byDay;
      final byAmount = b.expected.compareTo(a.expected);
      return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
    });
  Money sum(Money Function(ExpectedCollectionRow r) f) =>
      Money.sum(listed.map(f));
  final anyQist = listed.any((r) => r.onQist.isPositive);
  return ReportTable(
    id: 'expected_collections',
    title: 'Expected collections',
    period: ReportPeriod(asOf, last),
    columns: [
      const ReportColumn('Customer', CellKind.text),
      const ReportColumn('Phone', CellKind.text),
      const ReportColumn('First due', CellKind.text),
      const ReportColumn('Falls due', CellKind.money),
      if (anyQist) const ReportColumn('Of it on qist', CellKind.money),
      const ReportColumn('Promised for', CellKind.text),
      const ReportColumn('Promised', CellKind.money),
      const ReportColumn('Expected', CellKind.money),
      const ReportColumn('Late already', CellKind.money),
    ],
    rows: [
      for (final r in listed)
        ReportRow([
          r.name,
          r.phone ?? '',
          r.firstDue ?? '',
          r.fallsDue,
          if (anyQist) r.onQist,
          r.promisedFor ?? '',
          r.promised,
          r.expected,
          r.late,
        ], link: ReportLink.party(r.partyId, label: r.name)),
      ReportRow([
        'Total',
        listed.length == 1 ? '1 customer' : '${listed.length} customers',
        null,
        sum((r) => r.fallsDue),
        if (anyQist) sum((r) => r.onQist),
        null,
        sum((r) => r.promised),
        sum((r) => r.expected),
        sum((r) => r.late),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Expected', sum((r) => r.expected)),
      ReportFigure('Falls due', sum((r) => r.fallsDue)),
      ReportFigure('Promised', sum((r) => r.promised)),
      ReportFigure.count('Customers', listed.length),
    ],
    notes: [
      'From ${asOf.value} to ${last.value}. $_dueIsTheTerm',
      _expectedIsTheLarger,
    ],
  );
}

const _dueIsTheTerm =
    "A bill falls due its customer's credit days after its date, or thirty "
    'days where none are set; a bill sold on qist falls due by its '
    'instalments.';

const _expectedIsTheLarger =
    'Expected is the larger of what falls due and what was promised, never '
    'the two added: a promise is nearly always about the bills falling due. '
    'Late already is owed from before the week and is not in Expected.';

/// The day a row is first expected on: the earlier of its first bill due
/// and its promise.
String _earliest(ExpectedCollectionRow r) {
  final days = [?r.firstDue, ?r.promisedFor]..sort();
  return days.isEmpty ? '9999-12-31' : days.first;
}
