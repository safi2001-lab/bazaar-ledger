/// The pharmacy pack's papers (M49): the Schedule register an inspector asks
/// for, and the note an expiry return goes back to the distributor with.
///
/// Kept here, out of `ReportEngine._build` and out of the other groups'
/// files, so the engine carries the register as one case and the reports
/// other milestones add touch different lines.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// One movement of a Schedule medicine, as the register writes it.
final class ScheduleRegisterEntry {
  const ScheduleRegisterEntry({
    required this.date,
    required this.qty,
    required this.txnType,
    this.docNo,
    this.documentId,
    this.party,
    this.batch,
    this.patient,
    this.patientAddress,
    this.prescriber,
    this.prescriberRegNo,
    this.prescriptionRef,
  });

  final BusinessDate date;

  /// In the item's base unit; negative when it left the shop.
  final Qty qty;

  /// The stock ledger's word for it: `sale`, `purchase`, `sale_return`...
  final String txnType;
  final String? docNo;
  final String? documentId;

  /// Who was on the paper: the supplier of a delivery, the buyer on a bill.
  final String? party;
  final String? batch;
  final String? patient;
  final String? patientAddress;
  final String? prescriber;
  final String? prescriberRegNo;
  final String? prescriptionRef;
}

/// One Schedule medicine's page of the register.
final class ScheduleDrug {
  const ScheduleDrug({
    required this.itemId,
    required this.name,
    required this.unitCode,
    required this.opening,
    required this.entriesBefore,
    required this.entries,
    this.schedule,
    this.generic,
    this.manufacturer,
  });

  final String itemId;
  final String name;
  final String unitCode;

  /// `B`, `D` or `other`; null for an item since taken off the schedule
  /// whose registered sales still stand.
  final String? schedule;

  /// "Paracetamol 500 mg".
  final String? generic;
  final String? manufacturer;

  /// What was on hand when the period began.
  final Qty opening;

  /// How many entries the register had for it before the period, so a
  /// serial number is the same whichever period it is read over.
  final int entriesBefore;
  final List<ScheduleRegisterEntry> entries;
}

/// Where the pharmacy reports read from.
abstract interface class PharmacyReportSource {
  /// Every Schedule medicine — flagged now, or with a registered sale —
  /// with every movement of it in [period], oldest first.
  Future<List<ScheduleDrug>> scheduleRegister(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  });
}

/// The reports this file builds.
const pharmacyReportKinds = {ReportKind.scheduleRegister};

/// Builds [kind], one of [pharmacyReportKinds].
Future<ReportTable> buildPharmacyReport(
  ReportKind kind, {
  required PharmacyReportSource source,
  required String firmId,
  required ReportPeriod period,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.scheduleRegister => scheduleRegisterReport(
    period,
    await source.scheduleRegister(firmId, period, filters: filters),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M49 report'),
};

/// The Schedule B/D register, in the Punjab Drug Sale Rules' own columns:
/// serial, date, prescriber, patient, drug and its maker, batch, quantity
/// sold, quantity purchased and the balance — and a blank for the qualified
/// person's signature, which no app can give.
///
/// One page per medicine, its opening balance first, every movement after
/// it in date order. A sale is a line on its prescription; a delivery, a
/// return or a correction is a line too, because the balance has to be
/// explainable from the page alone.
ReportTable scheduleRegisterReport(
  ReportPeriod period,
  List<ScheduleDrug> drugs,
) {
  const width = 12;
  final rows = <ReportRow>[];
  var sold = Qty.zero;
  var bought = Qty.zero;
  var prescriptions = 0;
  for (final drug in drugs) {
    final describe = [
      drug.name,
      ?drug.generic,
      ?drug.manufacturer,
      if (drug.schedule case final s?)
        s == 'other' ? 'Schedule' : 'Schedule $s',
    ].join(' · ');
    rows.add(ReportRow.heading(describe, width));
    var balance = drug.opening;
    rows.add(
      ReportRow([
        period.from.value,
        null,
        'Opening balance',
        null,
        null,
        drug.name,
        drug.manufacturer,
        null,
        null,
        null,
        balance,
        null,
      ]),
    );
    var serial = drug.entriesBefore;
    for (final e in drug.entries) {
      serial++;
      balance += e.qty;
      final out = e.qty.isNegative ? -e.qty : null;
      final into = e.qty.isPositive ? e.qty : null;
      if (e.txnType == 'sale' && out != null) sold += out;
      if (e.txnType == 'purchase' && into != null) bought += into;
      if (e.patient != null) prescriptions++;
      rows.add(
        ReportRow(
          [
            e.date.value,
            serial,
            [
              _paper(e.txnType),
              ?e.docNo,
              if (e.patient == null) ?e.party,
            ].join(' '),
            switch (e.patient) {
              final p? => [p, ?e.patientAddress].join(', '),
              null => null,
            },
            switch (e.prescriber) {
              final p? => [
                p,
                if (e.prescriberRegNo case final r?) 'Reg $r',
                if (e.prescriptionRef case final r?) 'Rx $r',
              ].join(', '),
              null => null,
            },
            drug.name,
            drug.manufacturer,
            e.batch,
            out,
            into,
            balance,
            null,
          ],
          link: e.documentId == null
              ? null
              : ReportLink.document(e.documentId!, label: e.docNo ?? ''),
        ),
      );
    }
    rows.add(
      ReportRow([
        period.to.value,
        null,
        'Closing balance',
        null,
        null,
        drug.name,
        null,
        null,
        null,
        null,
        balance,
        null,
      ], style: RowStyle.subtotal),
    );
  }
  return ReportTable(
    id: 'schedule_register',
    title: 'Schedule register',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Serial', CellKind.count),
      ReportColumn('Paper', CellKind.text),
      ReportColumn('Patient', CellKind.text),
      ReportColumn('Prescriber', CellKind.text),
      ReportColumn('Drug', CellKind.text),
      ReportColumn('Manufacturer', CellKind.text),
      ReportColumn('Batch', CellKind.text),
      ReportColumn('Qty sold', CellKind.qty),
      ReportColumn('Qty purchased', CellKind.qty),
      ReportColumn('Balance', CellKind.qty),
      ReportColumn('Signature', CellKind.text),
    ],
    rows: rows,
    summary: [
      ReportFigure.count('Medicines', drugs.length),
      ReportFigure.count('Prescriptions', prescriptions),
    ],
    notes: [_whatIsCounted(sold, bought), _keepFor],
  );
}

String _whatIsCounted(Qty sold, Qty bought) =>
    'Schedule B and D medicines, and any the shop keeps the register for. '
    'Sold ${sold.display} and bought ${bought.display} in the period, '
    "in each medicine's own unit.";

const _keepFor =
    'Keep each original prescription, and this register, for three years '
    '(Punjab Drug Sale Rules 2007).';

String _paper(String txnType) => switch (txnType) {
  'sale' => 'Sale',
  'purchase' => 'Purchase',
  'sale_return' => 'Return in',
  'purchase_return' => 'Return to supplier',
  'adjustment' || 'wastage' => 'Correction',
  'opening' => 'Opening stock',
  'transfer_in' || 'transfer_out' => 'Moved',
  _ => txnType,
};

/// The note an expiry return goes back with: what went back to [supplier],
/// batch by batch, and how it was settled. Built as a table so it shares
/// the reports' PDF, Excel and share sheet.
ReportTable expiryReturnNote({
  required String shopName,
  required String supplier,
  required BusinessDate date,
  required ExpiryReturnDone done,
}) {
  final rows = [
    for (final b in done.batches)
      ReportRow([b.itemName, b.lotNo, b.expiry?.value, b.qty, b.mrp, b.value]),
    ReportRow([
      'Total',
      null,
      null,
      null,
      null,
      Money.sum([for (final b in done.batches) b.value]),
    ], style: RowStyle.total),
  ];
  return ReportTable(
    id: 'expiry_return_note',
    title: 'Expiry return note — $supplier',
    period: ReportPeriod.day(date),
    columns: const [
      ReportColumn('Medicine', CellKind.text),
      ReportColumn('Batch', CellKind.text),
      ReportColumn('Expiry', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('MRP', CellKind.money),
      ReportColumn('Value at cost', CellKind.money),
    ],
    rows: rows,
    summary: [
      ReportFigure('Credited to our account', done.credited),
      if (done.refunded.isPositive)
        ReportFigure('Paid back in cash', done.refunded),
    ],
    notes: [
      _sentBack(shopName, supplier, date, done.returnNos),
      'Received by (name, signature): ____________________',
    ],
  );
}

String _sentBack(
  String shopName,
  String supplier,
  BusinessDate date,
  List<String> returnNos,
) =>
    'From $shopName to $supplier: out-of-date and held stock returned on '
    '${date.value}, return ${returnNos.join(', ')}.';
