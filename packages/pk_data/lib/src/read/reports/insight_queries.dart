part of '../drift_report_source.dart';

/// The reads behind M67's reports: the ageing reports in the buckets the
/// shop sets, and the attention list.
///
/// The ageing reads are M8's and M58's queries with their buckets made the
/// shop's: each bound is a bound value and each bucket a CASE the database
/// sums, so the default buckets give the very figures the reports gave
/// before, and a wholesaler's ten thousand open bills are still summed in
/// SQLite rather than read into the phone.
///
/// The attention list is a handful of short reads, each the one a screen
/// already makes or the shape of one: the shelf below nothing, the money
/// accounts below nothing, the chase list's late udhaar (M38's owed rows),
/// the cheques in hand (M6's own select), today's voids from the audit log
/// (M31), today's sale lines below their cost, expired batches (M11) and
/// the FBR queue's offline bills (M59).
mixin _InsightQueries implements AgeingReportSource, AttentionReportSource {
  AppDatabase get _db;

  /// Binds [n] and returns its placeholder.
  static String _int(_Params q, int n) {
    q.variables.add(Variable<int>(n));
    return '?${q.variables.length}';
  }

  /// One summed column per bucket of [buckets], over the days in [days]:
  /// the first from [first] days, each after it from the day after the
  /// bound before, the last open-ended. Named `b0`, `b1`...
  static String _bucketSums(
    _Params q,
    AgeingBuckets buckets, {
    required String days,
    required String owed,
    required int first,
  }) {
    final b = buckets.bounds;
    final sums = <String>[];
    for (var i = 0; i <= b.length; i++) {
      final String when;
      if (i == b.length) {
        when = '$days > ${_int(q, b.last)}';
      } else {
        final from = i == 0 ? first : b[i - 1] + 1;
        when = '$days BETWEEN ${_int(q, from)} AND ${_int(q, b[i])}';
      }
      sums.add('COALESCE(SUM(CASE WHEN $when THEN $owed END), 0) AS b$i');
    }
    return sums.join(',\n                 ');
  }

  static List<Money> _buckets(QueryRow r, AgeingBuckets buckets) => [
    for (var i = 0; i <= buckets.bounds.length; i++)
      Money.paisa(r.read<int>('b$i')),
  ];

  @override
  Future<List<AgedBalance>> agedReceivables(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets,
  ) async {
    // M8's read: the same three parts as the khata's balance -- opening,
    // open bills and charges, less advances -- with the open part split by
    // age on the business date, so each row's total is the figure on that
    // khata. Only the bucket edges are new, and bound.
    final q = _Params(firmId)..text(asOf.value);
    final sums = _bucketSums(
      q,
      buckets,
      days: 'a.days',
      owed: 'a.owed',
      first: -100000,
    );
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name, p.opening_balance_paisa AS opening,
                 $sums,
                 COALESCE((
                   SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                   FROM journal_lines jl
                   JOIN accounts acc ON acc.id = jl.account_id
                   WHERE jl.party_id = p.id
                     AND jl.firm_id = p.firm_id
                     AND acc.system_key = 'customer_advances'
                     AND jl.deleted_at_utc IS NULL
                 ), 0) AS advance
          FROM parties p
          LEFT JOIN (
            SELECT d.party_id,
                   CAST(julianday(?2) - julianday(d.doc_date_local)
                        AS INTEGER) AS days,
                   d.balance_paisa AS owed
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'other_income')
              AND d.status = 'posted'
              AND d.balance_paisa <> 0
              AND d.deleted_at_utc IS NULL
          ) a ON a.party_id = p.id
          WHERE p.firm_id = ?1
            AND p.party_type IN ('customer', 'both')
            AND p.deleted_at_utc IS NULL
          GROUP BY p.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.parties,
            _db.documents,
            _db.journalLines,
            _db.accounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        AgedBalance(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          opening: Money.paisa(r.read<int>('opening')),
          buckets: _buckets(r, buckets),
          advance: Money.paisa(r.read<int>('advance')),
        ),
    ];
  }

  @override
  Future<List<AgedBalance>> agedPayables(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets,
  ) async {
    // M8's read: deliveries and expenses left on account, split by age. A
    // supplier's khata has no opening or advance of its own yet.
    final q = _Params(firmId)..text(asOf.value);
    final sums = _bucketSums(
      q,
      buckets,
      days: 'a.days',
      owed: 'a.owed',
      first: -100000,
    );
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name,
                 $sums
          FROM (
            SELECT d.party_id,
                   CAST(julianday(?2) - julianday(d.doc_date_local)
                        AS INTEGER) AS days,
                   d.balance_paisa AS owed
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('purchase_bill', 'expense')
              AND d.status = 'posted'
              AND d.balance_paisa <> 0
              AND d.party_id IS NOT NULL
              AND d.deleted_at_utc IS NULL
          ) a
          JOIN parties p ON p.id = a.party_id
          WHERE p.deleted_at_utc IS NULL
          GROUP BY p.id
          ''',
          variables: q.variables,
          readsFrom: {_db.parties, _db.documents},
        )
        .get();
    return [
      for (final r in rows)
        AgedBalance(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          buckets: _buckets(r, buckets),
        ),
    ];
  }

  @override
  Future<List<DueAgedBalance>> dueAgeingIn(
    String firmId,
    BusinessDate asOf,
    AgeingBuckets buckets, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // M58's read (udhaar_report_queries.dart), the late buckets the shop's.
    final q = _Params(firmId);
    final day = q.text(asOf.value);
    final sums = _bucketSums(
      q,
      buckets,
      days: 'b.late',
      owed: 'b.owed',
      first: 1,
    );
    final group = switch (filters.partyGroup) {
      null => '',
      ReportFilters.ungrouped => " AND COALESCE(TRIM(p.party_group), '') = ''",
      final g => ' AND TRIM(p.party_group) = ${q.text(g.trim())}',
    };
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name,
                 CASE WHEN p.party_type IN ('customer', 'both')
                      THEN p.opening_balance_paisa ELSE 0 END AS opening,
                 COALESCE(SUM(CASE WHEN b.late <= 0 THEN b.owed END), 0)
                   AS not_due,
                 $sums,
                 COALESCE((
                   SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                   FROM journal_lines jl
                   JOIN accounts acc ON acc.id = jl.account_id
                   WHERE jl.party_id = p.id
                     AND jl.firm_id = p.firm_id
                     AND acc.system_key = 'customer_advances'
                     AND jl.deleted_at_utc IS NULL
                 ), 0) AS advance
          FROM parties p
          LEFT JOIN (
            SELECT o.party_id AS party_id, o.owed AS owed,
                   CAST(julianday($day) - julianday(o.due_on) AS INTEGER)
                     AS late
            FROM (${owedRowsSql('d.firm_id = ?1')}) o
          ) b ON b.party_id = p.id
          WHERE p.firm_id = ?1
            AND ((p.party_type IN ('customer', 'both')
                  AND p.deleted_at_utc IS NULL)
                 OR b.party_id IS NOT NULL)
            $group
          GROUP BY p.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.parties,
            _db.documents,
            _db.journalLines,
            _db.accounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        DueAgedBalance(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          opening: Money.paisa(r.read<int>('opening')),
          notYetDue: Money.paisa(r.read<int>('not_due')),
          late: _buckets(r, buckets),
          advance: Money.paisa(r.read<int>('advance')),
        ),
    ];
  }

  @override
  Future<ShopExceptions> exceptions(
    String firmId,
    BusinessDate asOf, {
    required int lateDays,
    required DateTime nowUtc,
    required bool withCosts,
  }) async {
    final lots = await DriftAppQueries(_db).lotsOnHand(firmId);
    return ShopExceptions(
      shortItems: await _shortItems(firmId),
      overdrawn: await _overdrawn(firmId),
      lateUdhaar: await _lateUdhaar(firmId, asOf, lateDays),
      cheques: await DriftAppQueries(_db).chequesInHand(firmId),
      cancelled: await _cancelledOn(firmId, asOf),
      // Never read for a role that may not see costs.
      belowCost: withCosts ? await _belowCost(firmId, asOf) : const [],
      expired: [
        for (final l in lots)
          if (l.expiry != null &&
              l.expiry!.value.compareTo(asOf.value) < 0 &&
              l.qty.isPositive &&
              l.serial == null)
            l,
      ]..sort((a, b) => a.expiry!.value.compareTo(b.expiry!.value)),
      lateFbr: await _lateFbr(firmId, nowUtc),
    );
  }

  /// Every stocked item below nothing on the shelf, the furthest below
  /// first, with whether it is set to refuse such a sale (M53): its own
  /// rule, or the shop's where it has none.
  Future<List<ShortItem>> _shortItems(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, u.code AS unit_code, st.q AS qty,
                 COALESCE(i.negative_stock, (
                   SELECT setting_value FROM settings
                   WHERE firm_id = ?1 AND setting_key = ?2
                     AND deleted_at_utc IS NULL
                 ), ?3) AS rule
          FROM (
            SELECT s.item_id, SUM(s.qty_delta_thousandths) AS q
            FROM stock_ledger s
            WHERE s.firm_id = ?1 AND s.deleted_at_utc IS NULL
            GROUP BY s.item_id
          ) st
          JOIN items i ON i.id = st.item_id
          JOIN units u ON u.id = i.base_unit_id
          WHERE st.q < 0
            AND i.track_stock = 1
            AND i.deleted_at_utc IS NULL
          ORDER BY st.q, i.name_search
          ''',
          variables: [
            Variable<String>(firmId),
            const Variable<String>(negativeStockSettingKey),
            Variable<String>(NegativeStock.shopDefault.code),
          ],
          readsFrom: {_db.stockLedger, _db.items, _db.units, _db.settings},
        )
        .get();
    return [
      for (final r in rows)
        ShortItem(
          itemId: r.read<String>('id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qty: Qty.raw(r.read<int>('qty')),
          blocked: r.read<String>('rule') == NegativeStock.block.code,
        ),
    ];
  }

  /// The drawer, banks and wallets below nothing as the books stand: the
  /// accounts the cash flow counts as money (M33).
  ///
  /// Every line on them, by idx_jl_firm_account, with no date: the list is
  /// of today, the books hold nothing dated after it, and joining each line
  /// to its entry for a date tripled the read on a three-year book (M62's
  /// fixture). A line whose entry was deleted is deleted with it.
  Future<List<OverdrawnAccount>> _overdrawn(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts)
          SELECT a.id, a.name,
                 SUM(jl.debit_paisa - jl.credit_paisa) AS balance
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE jl.firm_id = ?1
            AND jl.account_id IN (SELECT id FROM money)
            AND jl.deleted_at_utc IS NULL
          GROUP BY a.id
          HAVING balance < 0
          ORDER BY balance
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.journalLines, _db.accounts, _db.paymentAccounts},
        )
        .get();
    return [
      for (final r in rows)
        OverdrawnAccount(
          accountId: r.read<String>('id'),
          name: r.read<String>('name'),
          balance: Money.paisa(r.read<int>('balance')),
        ),
    ];
  }

  /// Customers with udhaar [lateDays] or more past its due date on [asOf],
  /// the most owed first: the chase list's own rows (M38, M50).
  Future<List<LateUdhaar>> _lateUdhaar(
    String firmId,
    BusinessDate asOf,
    int lateDays,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name, p.phone, SUM(o.late_owed) AS owed,
                 MAX(o.late) AS late
          FROM (
            SELECT r.party_id, r.owed AS late_owed,
                   CAST(julianday(?2) - julianday(r.due_on) AS INTEGER)
                     AS late
            FROM (${owedRowsSql('d.firm_id = ?1')}) r
          ) o
          JOIN parties p ON p.id = o.party_id
          WHERE o.late >= ?3
          GROUP BY p.id
          HAVING owed > 0
          ORDER BY owed DESC, p.name_search
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(asOf.value),
            Variable<int>(lateDays),
          ],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    return [
      for (final r in rows)
        LateUdhaar(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          phone: r.readNullable<String>('phone'),
          owed: Money.paisa(r.read<int>('owed')),
          daysLate: r.read<int>('late'),
        ),
    ];
  }

  /// Every document cancelled on [day], by the audit row its void wrote in
  /// the same transaction (M31): who and when are the log's own envelope.
  Future<List<CancelledBill>> _cancelledOn(
    String firmId,
    BusinessDate day,
  ) async {
    final (from, to) = _StaffQueries._instants(ReportPeriod.day(day));
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_type, d.total_paisa, d.void_reason,
                 COALESCE(d.party_name_snapshot, p.name) AS party,
                 u.name AS who
          FROM audit_log a
          JOIN documents d ON d.id = a.entity_id
          LEFT JOIN parties p ON p.id = d.party_id
          JOIN users u ON u.id = a.created_by
          WHERE a.firm_id = ?1
            AND a.action_code = 'DOCUMENT_VOIDED'
            AND a.entity_table = 'documents'
            AND a.at_utc >= ?2 AND a.at_utc < ?3
            AND a.deleted_at_utc IS NULL
          ORDER BY a.at_utc, a.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<int>(from),
            Variable<int>(to),
          ],
          readsFrom: {_db.auditLog, _db.documents, _db.parties, _db.users},
        )
        .get();
    return [
      for (final r in rows)
        CancelledBill(
          documentId: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          docType: r.read<String>('doc_type'),
          total: Money.paisa(r.read<int>('total_paisa')),
          party: r.readNullable<String>('party'),
          reason: r.readNullable<String>('void_reason'),
          by: r.readNullable<String>('who'),
        ),
    ];
  }

  /// Every line of a bill dated [day] that sold for less than it cost, the
  /// biggest loss first. A free line under a scheme (M43) is free by
  /// design, and khula maal (M37) has no cost to fall below.
  Future<List<BelowCostLine>> _belowCost(
    String firmId,
    BusinessDate day,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no,
                 COALESCE(i.name, dl.item_name_snapshot) AS item,
                 dl.taxable_paisa AS sold, dl.cost_paisa AS cost
          FROM documents d
          JOIN document_lines dl ON dl.document_id = d.id
          LEFT JOIN items i ON i.id = dl.item_id
          WHERE d.firm_id = ?1
            AND d.doc_type = 'sale_invoice'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local = ?2
            AND dl.deleted_at_utc IS NULL
            AND dl.item_id IS NOT NULL
            AND dl.is_free_item = 0
            AND dl.taxable_paisa < dl.cost_paisa
          ORDER BY dl.cost_paisa - dl.taxable_paisa DESC, d.doc_seq
          ''',
          variables: [Variable<String>(firmId), Variable<String>(day.value)],
          readsFrom: {_db.documents, _db.documentLines, _db.items},
        )
        .get();
    return [
      for (final r in rows)
        BelowCostLine(
          documentId: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          itemName: r.read<String>('item'),
          sold: Money.paisa(r.read<int>('sold')),
          cost: Money.paisa(r.read<int>('cost')),
        ),
    ];
  }

  /// The FBR queue's bills made offline and still unsent a day after FBR
  /// could be reached again, oldest first, by M59's own rule
  /// (`offlineOverdue`) over the queue's own settings rows. Nothing for a
  /// shop that does not report.
  Future<List<LateFbrBill>> _lateFbr(String firmId, DateTime nowUtc) async {
    // M59's keys, written by the FBR queue (fbr_services.dart).
    const enabledKey = 'fbr.enabled';
    const sinceKey = 'fbr.since';
    const backAtKey = 'fbr.back_at';
    final held = {
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT setting_key, setting_value FROM settings
            WHERE firm_id = ?1 AND deleted_at_utc IS NULL
              AND setting_key IN (?2, ?3, ?4)
            ''',
                variables: [
                  Variable<String>(firmId),
                  const Variable<String>(enabledKey),
                  const Variable<String>(sinceKey),
                  const Variable<String>(backAtKey),
                ],
                readsFrom: {_db.settings},
              )
              .get())
        r.read<String>('setting_key'): r.read<String>('setting_value'),
    };
    final since = int.tryParse(held[sinceKey] ?? '');
    if (held[enabledKey] != '1' || since == null) return const [];
    final backMillis = int.tryParse(held[backAtKey] ?? '');
    final backAt = backMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(backMillis, isUtc: true);
    // Only the bills still waiting, through the partial index on
    // fbr_status, as the FBR screen reads them.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.created_at_utc,
                 (SELECT MIN(o.fbr_posted_at_utc) FROM documents o
                   WHERE o.firm_id = d.firm_id
                     AND o.fbr_status = 'posted'
                     AND o.fbr_posted_at_utc >= d.created_at_utc)
                   AS answered_after
          FROM documents d
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.created_at_utc >= ?2
            AND d.fbr_status = 'pending'
          ORDER BY d.created_at_utc
          LIMIT 1000
          ''',
          variables: [Variable<String>(firmId), Variable<int>(since)],
          readsFrom: {_db.documents},
        )
        .get();
    return [
      for (final r in rows)
        if (offlineOverdue(
          status: 'pending',
          connectionBackAtUtc: connectionBackFor(
            madeAtUtc: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('created_at_utc'),
              isUtc: true,
            ),
            answeredAtUtc: [
              switch (r.readNullable<int>('answered_after')) {
                final int ms => DateTime.fromMillisecondsSinceEpoch(
                  ms,
                  isUtc: true,
                ),
                null => null,
              },
              backAt,
            ],
          ),
          nowUtc: nowUtc,
        ))
          LateFbrBill(
            documentId: r.read<String>('id'),
            docNo: r.read<String>('doc_no'),
            madeOn: BusinessDate(r.read<String>('doc_date_local')),
          ),
    ];
  }
}
