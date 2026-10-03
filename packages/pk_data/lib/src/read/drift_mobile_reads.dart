import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// What is still owed on each instalment of every standing qist plan (M50),
/// as rows of `document_id`, `party_id`, `due_on` and `owed`, for the
/// udhaar reads (M38) to fall due instalment by instalment.
///
/// Nothing is ticked off anywhere: what has been paid on a plan is the
/// amount financed less what its bill still owes, and it pays the
/// instalments oldest first, so instalment `i` still owes
///
///     min(amount_i, max(0, cumulative_i - paid))
///
/// where `cumulative_i` is what the plan's instalments up to and including
/// `i` add up to — the same arithmetic as `settleOldestFirst` in pk_domain,
/// and a test holds the two together. A plan closed early brings every
/// remainder forward to the day it was closed.
///
/// [where] narrows the plans (`AND q.document_id = d.id` to correlate it
/// with an outer bill); rows owing nothing are left in for the caller to
/// drop, so the expression can be summed or filtered either way.
String qistOwedSql({String where = ''}) =>
    '''
    SELECT q.document_id AS document_id, q.party_id AS party_id,
           CASE WHEN q.closed_on_local IS NOT NULL
                     AND q.closed_on_local < i.due_on_local
                THEN q.closed_on_local ELSE i.due_on_local END AS due_on,
           MIN(i.amount_paisa, MAX(0,
             (SELECT SUM(j.amount_paisa) FROM qist_instalments j
               WHERE j.plan_id = i.plan_id AND j.seq <= i.seq
                 AND j.deleted_at_utc IS NULL)
             - MAX(0, q.financed_paisa - MAX(qd.balance_paisa, 0))
           )) AS owed
    FROM qist_plans q
    JOIN documents qd ON qd.id = q.document_id
    JOIN qist_instalments i ON i.plan_id = q.id AND i.deleted_at_utc IS NULL
    WHERE q.deleted_at_utc IS NULL $where
    ''';

/// Whether bill `d` is sold on a qist plan (M50): such a bill falls due by
/// its instalments, not by its customer's credit days.
const onQistSql =
    'EXISTS (SELECT 1 FROM qist_plans qp WHERE qp.document_id = d.id '
    'AND qp.deleted_at_utc IS NULL)';

/// The earliest day bill `d` still owes an instalment on, or null when it
/// is not sold on qist (M50): what the khata's due chip says of a qist
/// bill. An instalment still owes when what the instalments up to it add
/// up to is more than has been paid off the plan.
const qistNextDueSql = '''
  (SELECT MIN(CASE WHEN q.closed_on_local IS NOT NULL
                        AND q.closed_on_local < i.due_on_local
                   THEN q.closed_on_local ELSE i.due_on_local END)
     FROM qist_plans q
     JOIN qist_instalments i ON i.plan_id = q.id AND i.deleted_at_utc IS NULL
    WHERE q.document_id = d.id AND q.deleted_at_utc IS NULL
      AND (SELECT SUM(j.amount_paisa) FROM qist_instalments j
            WHERE j.plan_id = i.plan_id AND j.seq <= i.seq
              AND j.deleted_at_utc IS NULL)
          > MAX(0, q.financed_paisa - MAX(d.balance_paisa, 0)))
''';

/// [paper] with what a mobile shop's bill says besides the money (M50):
/// under each phone its IMEIs, the day its warranty ends and what PTA said
/// of it; under any other line under warranty the day it ends; and, on a
/// bill sold on qist, its instalments at the foot and its markup named as
/// such among the totals.
///
/// Read by the receipt read itself, so every paper a bill becomes — the
/// till roll, the PDF, the picture, a reprint — says the same. The warranty
/// day is the one the bill stamped when it was made; the PTA standing is
/// the phone's as the shop last found it out.
Future<ReceiptData> phonesOnPaper(
  AppDatabase db,
  String documentId,
  ReceiptData paper,
) async {
  final rows = await db
      .customSelect(
        'SELECT dl.warranty_until_local, l.serial, l.serial_2, l.pta_status '
        'FROM document_lines dl LEFT JOIN stock_lots l ON l.id = dl.lot_id '
        'WHERE dl.document_id = ? AND dl.deleted_at_utc IS NULL '
        'ORDER BY dl.line_no',
        variables: [Variable<String>(documentId)],
      )
      .get();
  var out = paper;
  // Zipped by position, as the tax columns are (M51): both reads order by
  // line number over the same rows, and a count that disagrees means one of
  // them skipped a line.
  if (rows.length == paper.lines.length &&
      rows.any(
        (r) =>
            r.readNullable<String>('serial') != null ||
            r.readNullable<String>('warranty_until_local') != null,
      )) {
    out = out.copyWith(
      lines: [
        for (var i = 0; i < rows.length; i++)
          switch (_lineDetails(rows[i])) {
            final more when more.isNotEmpty => paper.lines[i].withDetails(more),
            _ => paper.lines[i],
          },
      ],
    );
  }

  final plan = await db
      .customSelect(
        'SELECT q.id, q.down_payment_paisa, q.markup_paisa, q.financed_paisa, '
        '       q.due_day, q.guarantor_name, q.guarantor_cnic, '
        '       q.guarantor_phone, q.closed_on_local '
        'FROM qist_plans q WHERE q.document_id = ? AND q.deleted_at_utc IS NULL',
        variables: [Variable<String>(documentId)],
      )
      .getSingleOrNull();
  if (plan == null) return out;
  final instalments = await db
      .customSelect(
        'SELECT seq, due_on_local, amount_paisa FROM qist_instalments '
        'WHERE plan_id = ? AND deleted_at_utc IS NULL ORDER BY seq',
        variables: [Variable<String>(plan.read<String>('id'))],
      )
      .get();
  if (instalments.isEmpty) return out;
  final amounts = [
    for (final r in instalments) Money.paisa(r.read<int>('amount_paisa')),
  ];
  final first = BusinessDate(instalments.first.read<String>('due_on_local'));
  final last = BusinessDate(instalments.last.read<String>('due_on_local'));
  final markup = Money.paisa(plan.read<int>('markup_paisa'));
  final same = amounts.every((a) => a == amounts.first);
  final schedule = same
      ? '${amounts.length} x Rs ${amounts.first.amountOnly}'
      : '${amounts.length - 1} x Rs ${amounts.first.amountOnly} + '
            '1 x Rs ${amounts.last.amountOnly}';
  final guarantor = plan.readNullable<String>('guarantor_name');
  final guarantorCnic = plan.readNullable<String>('guarantor_cnic');
  final down = Money.paisa(plan.read<int>('down_payment_paisa'));
  final financed = Money.paisa(plan.read<int>('financed_paisa'));
  final dueDay = plan.read<int>('due_day');
  final onQist = markup.isPositive
      ? 'On qist Rs ${financed.amountOnly}, markup Rs ${markup.amountOnly} '
            'included'
      : 'On qist Rs ${financed.amountOnly}';
  final span = '${printedDate(first)} to ${printedDate(last)}';
  final qist = <String>[
    'QIST: Rs ${down.amountOnly} down, $schedule',
    'Due on day $dueDay of each month, $span',
    onQist,
    if (guarantor != null)
      'Guarantor: ${[guarantor, if (guarantorCnic != null) 'CNIC ${cnicDisplay(guarantorCnic)}', ?plan.readNullable<String>('guarantor_phone')].join(', ')}',
  ];
  return out.copyWith(
    // Before the shop's own footer, after anything the bill already says.
    footerLines: [...qist, ...out.footerLines],
    extraChargesLabel: markup.isPositive ? 'Qist markup' : null,
  );
}

List<String> _lineDetails(QueryRow r) {
  final imei1 = r.readNullable<String>('serial');
  final imei2 = r.readNullable<String>('serial_2');
  final pta = PtaStatus.fromCode(r.readNullable<String>('pta_status'));
  final until = r.readNullable<String>('warranty_until_local');
  return [
    if (imei1 != null)
      if (imei2 != null) ...[
        'IMEI 1: $imei1',
        'IMEI 2: $imei2',
      ] else if (pta != null)
        'IMEI: $imei1'
      else
        'Serial: $imei1',
    if (until != null) 'Warranty till ${printedDate(BusinessDate(until))}',
    ?pta?.printed,
  ];
}

/// The drift implementation of [MobileQueries].
final class DriftMobileReads implements MobileQueries {
  const DriftMobileReads(this._db);

  final AppDatabase _db;

  static const _unitSelect = '''
    SELECT l.id, l.item_id, i.name AS item_name, l.serial, l.serial_2,
           l.pta_status, l.pta_checked_on_local, l.received_at_utc,
           COALESCE((SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                      WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL), 0)
             AS on_hand
    FROM stock_lots l
    JOIN items i ON i.id = l.item_id
  ''';

  static PhoneUnit _unitFrom(QueryRow r) => PhoneUnit(
    lotId: r.read<String>('id'),
    itemId: r.read<String>('item_id'),
    itemName: r.read<String>('item_name'),
    imei1: r.read<String>('serial'),
    imei2: r.readNullable<String>('serial_2'),
    pta: PtaStatus.fromCode(r.readNullable<String>('pta_status')),
    ptaCheckedOn: switch (r.readNullable<String>('pta_checked_on_local')) {
      final d? => BusinessDate(d),
      null => null,
    },
    onHand: r.read<int>('on_hand') > 0,
  );

  @override
  Future<List<PhoneUnit>> findPhones(
    String firmId,
    String digits, {
    int limit = 30,
  }) async {
    final wanted = imeiDigits(digits);
    if (wanted.isEmpty) return const [];
    final rows = await _db
        .customSelect(
          '''
          $_unitSelect
          WHERE l.firm_id = ?1 AND l.deleted_at_utc IS NULL
            AND l.serial IS NOT NULL
            AND (instr(l.serial, ?2) > 0
                 OR instr(COALESCE(l.serial_2, ''), ?2) > 0)
          ORDER BY on_hand > 0 DESC, l.received_at_utc DESC, l.id DESC
          LIMIT ?3
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(wanted),
            Variable<int>(limit),
          ],
          readsFrom: {_db.stockLots, _db.items, _db.stockLedger},
        )
        .get();
    return [for (final r in rows) _unitFrom(r)];
  }

  @override
  Future<PhoneUnit?> phoneUnit(String firmId, String lotId) async {
    final row = await _db
        .customSelect(
          '$_unitSelect WHERE l.firm_id = ?1 AND l.id = ?2 '
          'AND l.serial IS NOT NULL',
          variables: [Variable<String>(firmId), Variable<String>(lotId)],
          readsFrom: {_db.stockLots, _db.items, _db.stockLedger},
        )
        .getSingleOrNull();
    return row == null ? null : _unitFrom(row);
  }

  @override
  Future<PhoneStory?> phoneStory(
    String firmId,
    String lotId, {
    bool withCosts = true,
  }) async {
    final unit = await phoneUnit(firmId, lotId);
    if (unit == null) return null;

    // The same IMEI may have come in under two items — sold new as one
    // model, bought back used as another — and is one phone all the same.
    final lots = [
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM stock_lots WHERE firm_id = ? '
                'AND deleted_at_utc IS NULL AND serial = ?',
                variables: [
                  Variable<String>(firmId),
                  Variable<String>(unit.imei1),
                ],
              )
              .get())
        r.read<String>('id'),
    ];
    final marks = List.filled(lots.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT s.occurred_on_local, s.txn_type, s.value_delta_paisa,
                 s.document_id, d.doc_no, d.doc_type, d.status, d.party_id,
                 COALESCE(d.party_name_snapshot, p.name) AS party_name,
                 dl.line_total_paisa, dl.warranty_until_local
          FROM stock_ledger s
          LEFT JOIN documents d ON d.id = s.document_id
          LEFT JOIN parties p ON p.id = d.party_id
          LEFT JOIN document_lines dl ON dl.id = s.document_line_id
          WHERE s.lot_id IN ($marks) AND s.deleted_at_utc IS NULL
          ORDER BY s.occurred_at_utc, s.id
          ''',
          variables: [for (final id in lots) Variable<String>(id)],
          readsFrom: {
            _db.stockLedger,
            _db.documents,
            _db.parties,
            _db.documentLines,
          },
        )
        .get();

    final events = <PhoneEvent>[];
    final bought = <String>[];
    for (final r in rows) {
      final type = r.read<String>('txn_type');
      final cancelled = r.readNullable<String>('status') == 'void';
      // A cancelled bill's goods coming back is the cancelling itself; the
      // sale is shown struck through, and that row says nothing more.
      if (type == 'adjustment' && cancelled) continue;
      final kind = switch (type) {
        'purchase' => PhoneEventKind.bought,
        'sale' => PhoneEventKind.sold,
        'sale_return' => PhoneEventKind.returned,
        'purchase_return' => PhoneEventKind.sentBack,
        'transfer_in' || 'transfer_out' => PhoneEventKind.moved,
        _ => PhoneEventKind.adjusted,
      };
      final documentId = r.readNullable<String>('document_id');
      if (kind == PhoneEventKind.bought && documentId != null) {
        bought.add(documentId);
      }
      events.add(
        PhoneEvent(
          kind: kind,
          on: BusinessDate(r.read<String>('occurred_on_local')),
          documentId: documentId,
          docNo: r.readNullable<String>('doc_no'),
          partyId: r.readNullable<String>('party_id'),
          partyName: r.readNullable<String>('party_name'),
          amount: switch (kind) {
            PhoneEventKind.sold => switch (r.readNullable<int>(
              'line_total_paisa',
            )) {
              final p? => Money.paisa(p),
              null => null,
            },
            PhoneEventKind.bought when withCosts => Money.paisa(
              r.read<int>('value_delta_paisa'),
            ),
            _ => null,
          },
          warrantyUntil: switch (r.readNullable<String>(
            'warranty_until_local',
          )) {
            final d? when kind == PhoneEventKind.sold => BusinessDate(d),
            _ => null,
          },
          cancelled: cancelled,
        ),
      );
    }

    UsedPhoneSeller? seller;
    String? boughtUsedOn;
    if (bought.isNotEmpty) {
      final used = await _db
          .customSelect(
            'SELECT u.document_id, u.party_id, u.seller_name, u.seller_cnic, '
            '       u.seller_phone, u.condition_note '
            'FROM used_phone_buys u JOIN documents d ON d.id = u.document_id '
            'WHERE u.deleted_at_utc IS NULL AND u.document_id IN '
            '(${List.filled(bought.length, '?').join(', ')}) '
            'ORDER BY d.doc_date_utc DESC LIMIT 1',
            variables: [for (final id in bought) Variable<String>(id)],
          )
          .getSingleOrNull();
      if (used != null) {
        seller = _sellerFrom(used);
        boughtUsedOn = used.read<String>('document_id');
      }
    }

    final claims = await _db
        .customSelect(
          'SELECT c.id, c.claimed_on_local, c.note, u.name AS by_name '
          'FROM warranty_claims c LEFT JOIN users u ON u.id = c.created_by '
          'WHERE c.lot_id IN ($marks) AND c.deleted_at_utc IS NULL '
          'ORDER BY c.claimed_on_local, c.created_at_utc',
          variables: [for (final id in lots) Variable<String>(id)],
        )
        .get();

    final item = await _db
        .customSelect(
          'SELECT warranty_kind FROM items WHERE id = ?',
          variables: [Variable<String>(unit.itemId)],
        )
        .getSingleOrNull();

    final story = PhoneStory(
      unit: unit,
      events: events,
      seller: seller,
      boughtUsedOn: boughtUsedOn,
      claims: [
        for (final c in claims)
          WarrantyClaim(
            id: c.read<String>('id'),
            on: BusinessDate(c.read<String>('claimed_on_local')),
            note: c.read<String>('note'),
            byName: c.readNullable<String>('by_name'),
          ),
      ],
      warrantyKind: WarrantyKind.fromCode(
        item?.readNullable<String>('warranty_kind'),
      ),
    );
    final sale = story.lastSale?.documentId;
    if (sale == null) return story;
    final plan = await _db
        .customSelect(
          'SELECT id FROM qist_plans WHERE document_id = ? '
          'AND deleted_at_utc IS NULL',
          variables: [Variable<String>(sale)],
        )
        .getSingleOrNull();
    return plan == null
        ? story
        : PhoneStory(
            unit: story.unit,
            events: story.events,
            seller: story.seller,
            boughtUsedOn: story.boughtUsedOn,
            claims: story.claims,
            warrantyKind: story.warrantyKind,
            qistPlanId: plan.read<String>('id'),
          );
  }

  static UsedPhoneSeller _sellerFrom(QueryRow r) => UsedPhoneSeller(
    name: r.read<String>('seller_name'),
    cnic: r.read<String>('seller_cnic'),
    phone: r.readNullable<String>('seller_phone'),
    partyId: r.readNullable<String>('party_id'),
    conditionNote: r.readNullable<String>('condition_note'),
  );

  @override
  Future<List<UsedPhoneBuy>> usedPhonesBought(
    String firmId, {
    BusinessDate? from,
    BusinessDate? to,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT u.document_id, u.party_id, u.seller_name, u.seller_cnic,
                 u.seller_phone, u.condition_note,
                 d.doc_no, d.doc_date_local, d.total_paisa, d.status,
                 l.id AS lot_id, l.serial, l.serial_2, l.pta_status,
                 COALESCE(i.name, (SELECT dl.item_name_snapshot
                                     FROM document_lines dl
                                    WHERE dl.document_id = d.id
                                    ORDER BY dl.line_no LIMIT 1))
                   AS item_name
          FROM used_phone_buys u
          JOIN documents d ON d.id = u.document_id
          LEFT JOIN stock_ledger s ON s.id = (
            SELECT s2.id FROM stock_ledger s2
             WHERE s2.document_id = d.id AND s2.txn_type = 'purchase'
               AND s2.lot_id IS NOT NULL AND s2.deleted_at_utc IS NULL
             ORDER BY s2.occurred_at_utc LIMIT 1)
          LEFT JOIN stock_lots l ON l.id = s.lot_id
          LEFT JOIN items i ON i.id = l.item_id
          WHERE u.firm_id = ?1 AND u.deleted_at_utc IS NULL
            AND (?2 IS NULL OR d.doc_date_local >= ?2)
            AND (?3 IS NULL OR d.doc_date_local <= ?3)
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from?.value),
            Variable<String>(to?.value),
          ],
          readsFrom: {
            _db.usedPhoneBuys,
            _db.documents,
            _db.stockLedger,
            _db.stockLots,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        UsedPhoneBuy(
          documentId: r.read<String>('document_id'),
          docNo: r.read<String>('doc_no'),
          on: BusinessDate(r.read<String>('doc_date_local')),
          seller: _sellerFrom(r),
          itemName: r.readNullable<String>('item_name') ?? '',
          imei1: r.readNullable<String>('serial') ?? '',
          imei2: r.readNullable<String>('serial_2'),
          pta: PtaStatus.fromCode(r.readNullable<String>('pta_status')),
          lotId: r.readNullable<String>('lot_id'),
          price: Money.paisa(r.read<int>('total_paisa')),
          cancelled: r.read<String>('status') == 'void',
        ),
    ];
  }

  @override
  Future<UsedPhoneSeller?> sellerByCnic(String firmId, String cnic) async {
    final row = await _db
        .customSelect(
          'SELECT u.document_id, u.party_id, u.seller_name, u.seller_cnic, '
          '       u.seller_phone, NULL AS condition_note '
          'FROM used_phone_buys u '
          'WHERE u.firm_id = ? AND u.seller_cnic = ? '
          'AND u.deleted_at_utc IS NULL '
          'ORDER BY u.created_at_utc DESC LIMIT 1',
          variables: [
            Variable<String>(firmId),
            Variable<String>(cnicDigits(cnic)),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _sellerFrom(row);
  }

  @override
  Future<List<QistPlan>> qistPlans(String firmId, {String? partyId}) => _plans(
    firmId,
    'AND (?2 IS NULL OR q.party_id = ?2)',
    [Variable<String>(partyId)],
  );

  @override
  Future<QistPlan?> qistPlan(String firmId, String planId) async =>
      (await _plans(firmId, 'AND q.id = ?2', [
        Variable<String>(planId),
      ])).firstOrNull;

  @override
  Future<QistPlan?> qistPlanForBill(String firmId, String documentId) async =>
      (await _plans(firmId, 'AND q.document_id = ?2', [
        Variable<String>(documentId),
      ])).firstOrNull;

  Future<List<QistPlan>> _plans(
    String firmId,
    String where,
    List<Variable<Object>> more,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT q.id, q.document_id, q.party_id, q.sold_on_local,
                 q.down_payment_paisa, q.markup_paisa, q.financed_paisa,
                 q.due_day, q.guarantor_name, q.guarantor_cnic,
                 q.guarantor_phone, q.closed_on_local, q.close_note,
                 d.doc_no, d.total_paisa, d.balance_paisa, d.status,
                 p.name AS party_name, p.phone AS party_phone
          FROM qist_plans q
          JOIN documents d ON d.id = q.document_id
          JOIN parties p ON p.id = q.party_id
          WHERE q.firm_id = ?1 AND q.deleted_at_utc IS NULL $where
          ORDER BY q.sold_on_local DESC, d.doc_seq DESC
          ''',
          variables: [Variable<String>(firmId), ...more],
          readsFrom: {_db.qistPlans, _db.documents, _db.parties},
        )
        .get();
    if (rows.isEmpty) return const [];
    final planIds = [for (final r in rows) r.read<String>('id')];
    final docIds = [for (final r in rows) r.read<String>('document_id')];
    final instalments = <String, List<Instalment>>{};
    for (final r
        in await _db
            .customSelect(
              'SELECT plan_id, seq, due_on_local, amount_paisa '
              'FROM qist_instalments WHERE deleted_at_utc IS NULL '
              'AND plan_id IN (${List.filled(planIds.length, '?').join(', ')}) '
              'ORDER BY plan_id, seq',
              variables: [for (final id in planIds) Variable<String>(id)],
              readsFrom: {_db.qistInstalments},
            )
            .get()) {
      (instalments[r.read<String>('plan_id')] ??= []).add(
        Instalment(
          seq: r.read<int>('seq'),
          dueOn: BusinessDate(r.read<String>('due_on_local')),
          amount: Money.paisa(r.read<int>('amount_paisa')),
        ),
      );
    }
    final goods = <String, List<String>>{};
    for (final r
        in await _db
            .customSelect(
              'SELECT dl.document_id, dl.item_name_snapshot, l.serial '
              'FROM document_lines dl '
              'LEFT JOIN stock_lots l ON l.id = dl.lot_id '
              'WHERE dl.deleted_at_utc IS NULL AND dl.document_id IN '
              '(${List.filled(docIds.length, '?').join(', ')}) '
              'ORDER BY dl.document_id, dl.line_no',
              variables: [for (final id in docIds) Variable<String>(id)],
              readsFrom: {_db.documentLines, _db.stockLots},
            )
            .get()) {
      (goods[r.read<String>('document_id')] ??= []).add(switch (r
          .readNullable<String>('serial')) {
        final imei? => '${r.read<String>('item_name_snapshot')} · $imei',
        null => r.read<String>('item_name_snapshot'),
      });
    }
    return [
      for (final r in rows)
        QistPlan(
          id: r.read<String>('id'),
          documentId: r.read<String>('document_id'),
          docNo: r.read<String>('doc_no'),
          partyId: r.read<String>('party_id'),
          partyName: r.read<String>('party_name'),
          partyPhone: r.readNullable<String>('party_phone'),
          soldOn: BusinessDate(r.read<String>('sold_on_local')),
          billTotal: Money.paisa(r.read<int>('total_paisa')),
          downPayment: Money.paisa(r.read<int>('down_payment_paisa')),
          markup: Money.paisa(r.read<int>('markup_paisa')),
          financed: Money.paisa(r.read<int>('financed_paisa')),
          billBalance: Money.paisa(r.read<int>('balance_paisa')),
          billCancelled: r.read<String>('status') == 'void',
          dueDay: r.read<int>('due_day'),
          instalments: instalments[r.read<String>('id')] ?? const [],
          guarantor: switch (r.readNullable<String>('guarantor_name')) {
            final name? => Guarantor(
              name: name,
              cnic: r.readNullable<String>('guarantor_cnic'),
              phone: r.readNullable<String>('guarantor_phone'),
            ),
            null => null,
          },
          closedOn: switch (r.readNullable<String>('closed_on_local')) {
            final d? => BusinessDate(d),
            null => null,
          },
          closeNote: r.readNullable<String>('close_note'),
          goods: goods[r.read<String>('document_id')] ?? const [],
        ),
    ];
  }
}
