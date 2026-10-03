/// Ageing in the buckets the shop sets (M67).
///
/// Udhaar by age (M8), Owed to suppliers and Udhaar by due date (M58) all
/// cut the money at 30, 60 and 90 days, because that is where the
/// textbook cuts it. A wholesaler who gives fifteen days' credit and calls
/// a customer on the sixteenth reads "0-30 days" as a column that hides the
/// very money he is chasing; a pharmacy distributor on monthly terms wants
/// 0-45 and 46-90. Zoho lets the shop set its own buckets, by amount, and
/// so does this: three bounds, "15, 30, 60", make 0-15, 16-30, 31-60 and
/// over 60 on the bill-age reports, and on the due-date one "not yet due",
/// 1-15, 16-30, 31-60 and over 60 days late. The ring drawn of the due-date
/// report (M46) follows whatever they are.
///
/// The bucketing is done by the database, each bound a bound value, so a
/// wholesaler's ten thousand open bills are summed in SQLite as before; the
/// default buckets give the very columns, titles and figures the reports
/// gave before, to the paisa, and a test holds the two side by side.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_table.dart';

/// Where the shop cuts its ageing: the last day of each bucket but the
/// open-ended last one, in days, ascending.
final class AgeingBuckets {
  const AgeingBuckets(this.bounds);

  /// 0-30, 31-60, 61-90 and over 90: the reports' own until the shop
  /// chooses.
  static const standard = AgeingBuckets([30, 60, 90]);

  /// At most this many bounds, so at most six buckets: a seventh column
  /// would not be read on a phone.
  static const mostBounds = 5;

  /// No bucket ends past ten years.
  static const longest = 3650;

  final List<int> bounds;

  /// Whether these can bucket anything: one to [mostBounds] bounds, each a
  /// day or more and each past the one before.
  bool get isValid {
    if (bounds.isEmpty || bounds.length > mostBounds) return false;
    var last = 0;
    for (final b in bounds) {
      if (b <= last || b > longest) return false;
      last = b;
    }
    return true;
  }

  bool get isStandard => _same(bounds, standard.bounds);

  /// "15, 30, 60" read as typed, spaces and stray commas aside; null for
  /// anything that does not make valid buckets.
  static AgeingBuckets? tryParse(String text) {
    final parts = text
        .split(RegExp(r'[,\s/]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final bounds = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      bounds.add(n);
    }
    final buckets = AgeingBuckets(bounds);
    return buckets.isValid ? buckets : null;
  }

  /// The bucket columns by the bill's age: `0-30 days` ... `Over 90 days`.
  List<String> get ageColumns => [
    for (var i = 0; i < bounds.length; i++)
      '${i == 0 ? 0 : bounds[i - 1] + 1}-${bounds[i]} days',
    'Over ${bounds.last} days',
  ];

  /// The bucket columns by days past due, after "Not yet due":
  /// `1-30 days late` ... `Over 90 days late`.
  List<String> get lateColumns => [
    for (var i = 0; i < bounds.length; i++)
      '${i == 0 ? 1 : bounds[i - 1] + 1}-${bounds[i]} days late',
    'Over ${bounds.last} days late',
  ];

  /// "0-15 / 16-30 / 31-60 / 60+", for a chip.
  String get label => [
    for (var i = 0; i < bounds.length; i++)
      '${i == 0 ? 0 : bounds[i - 1] + 1}-${bounds[i]}',
    '${bounds.last}+',
  ].join(' / ');

  /// "15, 30, 60": what the shop types, and what the phone keeps.
  String get typed => bounds.join(', ');

  @override
  bool operator ==(Object other) =>
      other is AgeingBuckets && _same(other.bounds, bounds);

  @override
  int get hashCode => Object.hashAll(bounds);

  @override
  String toString() => label;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What one party owes, or is owed, by the age of each open bill (M67).
final class AgedBalance {
  const AgedBalance({
    required this.name,
    required this.buckets,
    this.partyId,
    this.opening = Money.zero,
    this.advance = Money.zero,
  });

  final String? partyId;
  final String name;

  /// The balance brought forward when the khata was opened, undated.
  final Money opening;

  /// The open bills in each bucket, youngest first; one more than the
  /// buckets' bounds.
  final List<Money> buckets;

  /// Money held for them, which comes off what they owe.
  final Money advance;

  /// The khata's balance.
  Money get owed => opening + Money.sum(buckets) - advance;
}

/// What one customer owes, by how late each part of it is against its due
/// date (M67): M58's row in the shop's buckets.
final class DueAgedBalance {
  const DueAgedBalance({
    required this.partyId,
    required this.name,
    required this.late,
    this.notYetDue = Money.zero,
    this.opening = Money.zero,
    this.advance = Money.zero,
  });

  final String partyId;
  final String name;

  /// Open bills inside the customer's terms, the day they fall due
  /// included.
  final Money notYetDue;

  /// Past due, in each bucket of days late; one more than the bounds.
  final List<Money> late;
  final Money opening;
  final Money advance;

  Money get overdue => Money.sum(late);

  /// The khata's balance.
  Money get owed => opening + notYetDue + overdue - advance;
}

/// Where the ageing reports read from in the shop's buckets (M67).
abstract interface class AgeingReportSource {
  /// Every customer with anything open, their open bills bucketed by age on
  /// [asOf].
  Future<List<AgedBalance>> agedReceivables(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets,
  );

  /// Every supplier the shop owes, bucketed the same way.
  Future<List<AgedBalance>> agedPayables(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets,
  );

  /// Every customer with anything open, bucketed by days past due on
  /// [asOf], narrowed by party group: M58's `dueAgeing` in these buckets.
  Future<List<DueAgedBalance>> dueAgeingIn(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets, {
    ReportFilters filters = ReportFilters.none,
  });
}

/// The shop's buckets, said under any ageing report built in other than
/// the standard ones.
String _theShopsBuckets(AgeingBuckets b) =>
    "Buckets are the shop's own: ${b.label} days.";

const _openingHasNoDate =
    'Opening is the balance brought forward when the khata was started, '
    'which has no date to age from.';

const _advanceComesOff =
    'Advance is money the shop is holding for the customer, and comes off '
    'what they owe.';

/// Udhaar by age in [buckets] (M67): Udhaar by age (M8), cut where the
/// shop cuts it.
ReportTable receivablesAged(
  BusinessDate asOf,
  List<AgedBalance> rows,
  AgeingBuckets buckets,
) => _aged(
  id: 'receivables',
  title: 'Udhaar by age',
  who: 'Customer',
  asOf: asOf,
  rows: rows,
  buckets: buckets,
);

/// Owed to suppliers in [buckets] (M67).
ReportTable payablesAged(
  BusinessDate asOf,
  List<AgedBalance> rows,
  AgeingBuckets buckets,
) => _aged(
  id: 'payables',
  title: 'Owed to suppliers',
  who: 'Supplier',
  asOf: asOf,
  rows: rows,
  buckets: buckets,
);

ReportTable _aged({
  required String id,
  required String title,
  required String who,
  required BusinessDate asOf,
  required List<AgedBalance> rows,
  required AgeingBuckets buckets,
}) {
  final width = buckets.bounds.length + 1;
  Money bucket(AgedBalance r, int i) =>
      i < r.buckets.length ? r.buckets[i] : Money.zero;
  // The most in the oldest bucket first, then the most owed, then by name,
  // as Udhaar by age has always sorted.
  final owing = rows.where((r) => !r.owed.isZero).toList()
    ..sort((a, b) {
      final byOld = bucket(b, width - 1).compareTo(bucket(a, width - 1));
      if (byOld != 0) return byOld;
      final byOwed = b.owed.compareTo(a.owed);
      return byOwed != 0 ? byOwed : a.name.compareTo(b.name);
    });
  Money sum(Money Function(AgedBalance r) f) => Money.sum(owing.map(f));
  final anyOpening = owing.any((r) => !r.opening.isZero);
  final anyAdvance = owing.any((r) => !r.advance.isZero);
  final columns = buckets.ageColumns;
  return ReportTable(
    id: id,
    title: title,
    period: ReportPeriod.day(asOf),
    columns: [
      ReportColumn(who, CellKind.text),
      const ReportColumn('Opening', CellKind.money),
      for (final c in columns) ReportColumn(c, CellKind.money),
      const ReportColumn('Advance', CellKind.money),
      const ReportColumn('Owed', CellKind.money),
    ],
    rows: [
      for (final r in owing)
        ReportRow(
          [
            r.name,
            r.opening,
            for (var i = 0; i < width; i++) bucket(r, i),
            -r.advance,
            r.owed,
          ],
          link: r.partyId == null
              ? null
              : ReportLink.party(r.partyId!, label: r.name),
        ),
      ReportRow([
        'Total',
        sum((r) => r.opening),
        for (var i = 0; i < width; i++) sum((r) => bucket(r, i)),
        -sum((r) => r.advance),
        sum((r) => r.owed),
      ], style: RowStyle.total),
    ],
    notes: [
      'Aged from the date of each bill still open.',
      if (!buckets.isStandard) _theShopsBuckets(buckets),
      if (anyOpening) _openingHasNoDate,
      if (anyAdvance) _advanceComesOff,
    ],
    bucketColumns: columns,
  );
}

/// The first column of the due-date report's buckets: what is still
/// inside its terms.
const notYetDueColumn = 'Not yet due';

/// Udhaar by due date in [buckets] (M67): M58's report, late money cut
/// where the shop cuts it, the latest on the right.
ReportTable receivablesByDueDateIn(
  BusinessDate asOf,
  List<DueAgedBalance> rows,
  AgeingBuckets buckets,
) {
  final width = buckets.bounds.length + 1;
  Money late(DueAgedBalance r, int i) =>
      i < r.late.length ? r.late[i] : Money.zero;
  final owing =
      rows
          .where(
            (r) => !r.owed.isZero || !r.notYetDue.isZero || !r.overdue.isZero,
          )
          .toList()
        ..sort((a, b) {
          for (var i = width - 1; i >= 0; i--) {
            final c = late(b, i).compareTo(late(a, i));
            if (c != 0) return c;
          }
          final byOwed = b.owed.compareTo(a.owed);
          return byOwed != 0 ? byOwed : a.name.compareTo(b.name);
        });
  Money sum(Money Function(DueAgedBalance r) f) => Money.sum(owing.map(f));
  final anyOpening = owing.any((r) => !r.opening.isZero);
  final anyAdvance = owing.any((r) => !r.advance.isZero);
  final overdue = sum((r) => r.overdue);
  final behind = owing.where((r) => r.overdue.isPositive).length;
  final columns = [notYetDueColumn, ...buckets.lateColumns];
  return ReportTable(
    id: 'receivables_by_due_date',
    title: 'Udhaar by due date',
    period: ReportPeriod.day(asOf),
    columns: [
      const ReportColumn('Customer', CellKind.text),
      for (final title in columns) ReportColumn(title, CellKind.money),
      const ReportColumn('Opening', CellKind.money),
      const ReportColumn('Advance', CellKind.money),
      const ReportColumn('Owed', CellKind.money),
    ],
    rows: [
      for (final r in owing)
        ReportRow([
          r.name,
          r.notYetDue,
          for (var i = 0; i < width; i++) late(r, i),
          r.opening,
          -r.advance,
          r.owed,
        ], link: ReportLink.party(r.partyId, label: r.name)),
      ReportRow([
        'Total',
        sum((r) => r.notYetDue),
        for (var i = 0; i < width; i++) sum((r) => late(r, i)),
        sum((r) => r.opening),
        -sum((r) => r.advance),
        sum((r) => r.owed),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Owed', sum((r) => r.owed)),
      ReportFigure('Overdue', overdue),
      ReportFigure.count('Customers late', behind),
    ],
    notes: [
      _dueIsTheTerm,
      if (!buckets.isStandard) _theShopsBuckets(buckets),
      if (anyOpening) _openingHasNoDueDate,
      if (anyAdvance) _advanceComesOff,
    ],
    bucketColumns: columns,
  );
}

const _dueIsTheTerm =
    "A bill is due its customer's credit days after its date, or thirty "
    'days where none are set; it is late from the day after. Owed is the '
    "khata's balance, and the total is Udhaar by age's.";

const _openingHasNoDueDate =
    'Opening is the balance brought forward when the khata was started: it '
    'has no bill date, so no day it falls due.';
