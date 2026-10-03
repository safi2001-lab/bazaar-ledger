/// The mobile-shop pack's reports (M50): the register of used phones bought
/// over the counter, for the police and the market association, and the
/// instalments every phone sold on qist is paid off by.
///
/// Kept here, out of `ReportEngine._build` and the other groups' files, so
/// the engine carries them as one case and the reports other milestones add
/// touch different lines.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// Where the mobile-shop reports read from.
abstract interface class MobileReportSource {
  /// Every used phone bought over the counter in [period], newest first.
  Future<List<UsedPhoneBuy>> usedPhonesBought(
    String firmId,
    ReportPeriod period,
  );

  /// Every qist plan, newest first.
  Future<List<QistPlan>> qistPlans(String firmId);
}

/// The reports this file builds.
const mobileReportKinds = {
  ReportKind.usedPhonesRegister,
  ReportKind.qistInstalments,
};

/// Builds [kind], one of [mobileReportKinds].
Future<ReportTable> buildMobileReport(
  ReportKind kind, {
  required MobileReportSource source,
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.usedPhonesRegister => usedPhonesRegisterReport(
    period,
    await source.usedPhonesBought(firmId, period),
  ),
  ReportKind.qistInstalments => qistInstalmentsReport(today, [
    for (final p in await source.qistPlans(firmId))
      if (filters.partyId == null || p.partyId == filters.partyId) p,
  ]),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M50 report'),
};

/// The used phones bought register: date, the paper, the seller by name,
/// CNIC and phone, the phone by model and both IMEIs, its PTA standing,
/// what was paid, and what state it was in — the columns a police station
/// or a market association asks a mobile shop to keep **[practice as
/// reported; no written rule was found and none is claimed]**.
ReportTable usedPhonesRegisterReport(
  ReportPeriod period,
  List<UsedPhoneBuy> bought,
) {
  final standing = [
    for (final b in bought)
      if (!b.cancelled) b,
  ];
  return ReportTable(
    id: 'used_phones_register',
    title: 'Used phones bought',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Purchase', CellKind.text),
      ReportColumn('Seller', CellKind.text),
      ReportColumn('CNIC', CellKind.text),
      ReportColumn('Seller phone', CellKind.text),
      ReportColumn('Phone', CellKind.text),
      ReportColumn('IMEI 1', CellKind.text),
      ReportColumn('IMEI 2', CellKind.text),
      ReportColumn('PTA', CellKind.text),
      ReportColumn('Paid', CellKind.money),
      ReportColumn('Condition', CellKind.text),
    ],
    rows: [
      for (final b in bought)
        ReportRow(
          [
            b.on.value,
            b.cancelled ? '${b.docNo} (cancelled)' : b.docNo,
            b.seller.name,
            cnicDisplay(b.seller.cnic),
            b.seller.phone,
            b.itemName,
            b.imei1,
            b.imei2,
            b.pta?.printed,
            b.price,
            b.seller.conditionNote,
          ],
          link: ReportLink.document(
            b.documentId,
            label: b.docNo,
            docType: 'purchase_bill',
          ),
        ),
      if (standing.isNotEmpty)
        ReportRow([
          'Total',
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          Money.sum([for (final b in standing) b.price]),
          null,
        ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Phones bought', standing.length),
      ReportFigure(
        'Paid to sellers',
        Money.sum([for (final b in standing) b.price]),
      ),
    ],
    notes: const [_registerNote],
  );
}

/// Every phone sold on qist: whose, which bill, what it cost, what came
/// down, what is on qist, what has been paid, what is still to pay, what of
/// it is late, and when the next instalment falls due.
ReportTable qistInstalmentsReport(BusinessDate today, List<QistPlan> plans) {
  final live = [
    for (final p in plans)
      if (!p.billCancelled) p,
  ];
  String standing(QistPlan p) => switch (p.standingOn(today)) {
    QistStanding.running => 'Running',
    QistStanding.overdue => 'Overdue',
    QistStanding.paidOff => 'Paid off',
    QistStanding.closed => 'Closed early',
    QistStanding.cancelled => 'Cancelled',
  };
  return ReportTable(
    id: 'qist_instalments',
    title: 'Instalments',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Bill', CellKind.text),
      ReportColumn('Sold', CellKind.text),
      ReportColumn('Phone', CellKind.text),
      ReportColumn('Bill total', CellKind.money),
      ReportColumn('Down', CellKind.money),
      ReportColumn('On qist', CellKind.money),
      ReportColumn('Paid', CellKind.money),
      ReportColumn('Still to pay', CellKind.money),
      ReportColumn('Overdue', CellKind.money),
      ReportColumn('Instalments paid', CellKind.text),
      ReportColumn('Next due', CellKind.text),
      ReportColumn('Standing', CellKind.text),
    ],
    rows: [
      for (final p in plans)
        ReportRow(
          [
            p.partyName,
            p.docNo,
            p.soldOn.value,
            p.goods.join(', '),
            p.billTotal,
            p.downPayment,
            p.financed,
            p.billCancelled ? Money.zero : p.paid,
            p.billCancelled ? Money.zero : p.left,
            p.overdueOn(today),
            '${p.paidCount} of ${p.count}',
            p.billCancelled ? null : p.nextOpen?.dueOn.value,
            standing(p),
          ],
          link: ReportLink.document(
            p.documentId,
            label: p.docNo,
            docType: 'sale_invoice',
          ),
        ),
      if (live.isNotEmpty)
        ReportRow([
          'Total',
          null,
          null,
          null,
          Money.sum([for (final p in live) p.billTotal]),
          Money.sum([for (final p in live) p.downPayment]),
          Money.sum([for (final p in live) p.financed]),
          Money.sum([for (final p in live) p.paid]),
          Money.sum([for (final p in live) p.left]),
          Money.sum([for (final p in live) p.overdueOn(today)]),
          null,
          null,
          null,
        ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count(
        'Plans running',
        live.where((p) => p.left.isPositive).length,
      ),
      ReportFigure('Still to pay', Money.sum([for (final p in live) p.left])),
      ReportFigure(
        'Overdue',
        Money.sum([for (final p in live) p.overdueOn(today)]),
      ),
    ],
    notes: const [_instalmentsNote],
  );
}

const _registerNote =
    'Every used phone bought over the counter, with the seller as they gave '
    'themselves on the day. Photographs of the CNIC and the phone are kept '
    'on the phone they were taken on, never sent anywhere.';

const _instalmentsNote =
    'What is paid is read off each bill: every receipt pays the oldest '
    'instalment first. The markup, where one was charged, is in the bill '
    'total and in what is on qist.';
