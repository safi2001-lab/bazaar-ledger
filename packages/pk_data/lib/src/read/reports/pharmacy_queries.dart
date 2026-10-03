part of '../drift_report_source.dart';

/// The reads behind the pharmacy reports (M49): the Schedule register.
///
/// Read straight off the stock ledger — every strip that came in or went out
/// is already there, with its batch and the paper it moved on — and the
/// prescriptions a sale was registered against. Nothing is copied into a
/// register table that could disagree with the shelf: the register IS the
/// shelf, for the medicines that need one.
mixin _PharmacyQueries implements PharmacyReportSource {
  AppDatabase get _db;

  /// Moving goods between the shop floor and a godown changes no balance
  /// the register keeps, so those two rows are left out of it entirely.
  static const _moved = "('transfer_in', 'transfer_out')";

  @override
  Future<List<ScheduleDrug>> scheduleRegister(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // The firm and the period's first day only: what came before it is
    // the opening, and what is in it is read per medicine below.
    final variables = <Variable<Object>>[
      Variable<String>(firmId),
      Variable<String>(period.from.value),
      if (filters.itemId case final id?) Variable<String>(id),
    ];
    final item = filters.itemId == null ? '' : 'AND i.id = ?3';
    final drugs = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, i.schedule_class, i.generic_name, i.strength,
                 i.manufacturer, u.code AS unit_code,
                 COALESCE((
                   SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                   WHERE s.firm_id = i.firm_id AND s.item_id = i.id
                     AND s.deleted_at_utc IS NULL
                     AND s.txn_type NOT IN $_moved
                     AND s.occurred_on_local < ?2
                 ), 0) AS opening,
                 (SELECT COUNT(*) FROM stock_ledger s
                   WHERE s.firm_id = i.firm_id AND s.item_id = i.id
                     AND s.deleted_at_utc IS NULL
                     AND s.txn_type NOT IN $_moved
                     AND s.occurred_on_local < ?2) AS before_count
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ?1 AND i.deleted_at_utc IS NULL
            AND (i.schedule_class IS NOT NULL
                 OR EXISTS (SELECT 1 FROM prescriptions rx
                             WHERE rx.firm_id = i.firm_id
                               AND rx.item_id = i.id
                               AND rx.deleted_at_utc IS NULL))
            $item
          ORDER BY i.name_search
          ''',
          variables: variables,
          readsFrom: {_db.items, _db.stockLedger, _db.prescriptions},
        )
        .get();

    final out = <ScheduleDrug>[];
    for (final d in drugs) {
      final itemId = d.read<String>('id');
      final rows = await _db
          .customSelect(
            '''
            SELECT s.occurred_on_local, s.qty_delta_thousandths, s.txn_type,
                   doc.id AS document_id, doc.doc_no,
                   COALESCE(doc.party_name_snapshot, p.name) AS party,
                   l.lot_no, rx.patient_name, rx.patient_address,
                   rx.prescriber_name, rx.prescriber_reg_no,
                   rx.prescription_ref
            FROM stock_ledger s
            LEFT JOIN documents doc ON doc.id = s.document_id
            LEFT JOIN parties p ON p.id = doc.party_id
            LEFT JOIN stock_lots l ON l.id = s.lot_id
            LEFT JOIN prescriptions rx
              ON rx.document_line_id = s.document_line_id
             AND rx.deleted_at_utc IS NULL
            WHERE s.firm_id = ?1 AND s.item_id = ?4
              AND s.deleted_at_utc IS NULL
              AND s.txn_type NOT IN $_moved
              AND s.occurred_on_local BETWEEN ?2 AND ?3
            ORDER BY s.occurred_on_local, s.occurred_at_utc, s.id
            ''',
            variables: [
              Variable<String>(firmId),
              Variable<String>(period.from.value),
              Variable<String>(period.to.value),
              Variable<String>(itemId),
            ],
            readsFrom: {
              _db.stockLedger,
              _db.documents,
              _db.parties,
              _db.stockLots,
              _db.prescriptions,
            },
          )
          .get();
      final generic = d.readNullable<String>('generic_name');
      final strength = d.readNullable<String>('strength');
      out.add(
        ScheduleDrug(
          itemId: itemId,
          name: d.read<String>('name'),
          unitCode: d.read<String>('unit_code'),
          schedule: d.readNullable<String>('schedule_class'),
          generic: generic == null
              ? null
              : strength == null
              ? generic
              : '$generic $strength',
          manufacturer: d.readNullable<String>('manufacturer'),
          opening: Qty.raw(d.read<int>('opening')),
          entriesBefore: d.read<int>('before_count'),
          entries: [
            for (final r in rows)
              ScheduleRegisterEntry(
                date: BusinessDate(r.read<String>('occurred_on_local')),
                qty: Qty.raw(r.read<int>('qty_delta_thousandths')),
                txnType: r.read<String>('txn_type'),
                documentId: r.readNullable<String>('document_id'),
                docNo: r.readNullable<String>('doc_no'),
                party: r.readNullable<String>('party'),
                batch: r.readNullable<String>('lot_no'),
                patient: r.readNullable<String>('patient_name'),
                patientAddress: r.readNullable<String>('patient_address'),
                prescriber: r.readNullable<String>('prescriber_name'),
                prescriberRegNo: r.readNullable<String>('prescriber_reg_no'),
                prescriptionRef: r.readNullable<String>('prescription_ref'),
              ),
          ],
        ),
      );
    }
    return out;
  }
}
