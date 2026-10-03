part of '../drift_report_source.dart';

/// The read behind Expected collections (M54), on the udhaar pack's own
/// terms: a bill's due date and the qist instalments are the rows the chase
/// list reads (`owedRowsSql`, M38 and M50), and the promises are its own
/// (`dueParties`), so this report cannot say a customer owes this week what
/// the chase list says they do not.
mixin _CollectionsQueries implements CollectionsReportSource {
  AppDatabase get _db;

  @override
  Future<List<ExpectedCollectionRow>> expectedCollections(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final from = q.text(asOf.value);
    final to = q.text(asOf.addDays(expectedCollectionDays - 1).value);
    final narrow = StringBuffer();
    if (filters.partyId case final id?) {
      narrow.write(' AND ps.id = ${q.text(id)}');
    }
    switch (filters.partyGroup) {
      case null:
        break;
      case ReportFilters.ungrouped:
        narrow.write(" AND COALESCE(TRIM(ps.party_group), '') = ''");
      case final g:
        narrow.write(' AND TRIM(ps.party_group) = ${q.text(g.trim())}');
    }
    // Summed by the database, per customer: a wholesaler's open bills are
    // never read into the phone. A customer in credit overall is left out,
    // as the chase list leaves them, and nobody is expected to pay more
    // than they owe in all.
    final rows = await _db
        .customSelect(
          '''
          WITH due AS (
            ${owedRowsSql('d.firm_id = ?1 AND p.deleted_at_utc IS NULL')}
          ),
          qist AS (
            SELECT qo.party_id, qo.owed, qo.due_on
            FROM (${qistOwedSql()}) qo
            JOIN documents d ON d.id = qo.document_id
            WHERE d.firm_id = ?1 AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL AND d.balance_paisa > 0
              AND qo.owed > 0
          ),
          per_party AS (
            SELECT party_id,
                   SUM(CASE WHEN due_on BETWEEN $from AND $to
                            THEN owed ELSE 0 END) AS falls_due,
                   MIN(CASE WHEN due_on BETWEEN $from AND $to
                            THEN due_on END) AS first_due,
                   SUM(CASE WHEN due_on < $from THEN owed ELSE 0 END)
                     AS late
            FROM due
            GROUP BY party_id
          ),
          on_qist AS (
            SELECT party_id, SUM(owed) AS owed FROM qist
            WHERE due_on BETWEEN $from AND $to
            GROUP BY party_id
          )
          SELECT ps.id, ps.name, ps.phone, ps.balance_paisa,
                 pp.falls_due, pp.first_due, pp.late,
                 COALESCE(oq.owed, 0) AS on_qist
          FROM per_party pp
          JOIN (${DriftAppQueries.partySelectSql} WHERE p.firm_id = ?1) ps
            ON ps.id = pp.party_id
          LEFT JOIN on_qist oq ON oq.party_id = pp.party_id
          WHERE ps.balance_paisa > 0 $narrow
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.journalLines,
            _db.accounts,
            _db.payments,
          },
        )
        .get();

    Money capped(int paisa, int owed) =>
        Money.paisa(paisa < owed ? paisa : owed);
    final out = <String, ExpectedCollectionRow>{};
    for (final r in rows) {
      final owed = r.read<int>('balance_paisa');
      out[r.read<String>('id')] = ExpectedCollectionRow(
        partyId: r.read<String>('id'),
        name: r.read<String>('name'),
        phone: r.readNullable<String>('phone'),
        fallsDue: capped(r.read<int>('falls_due'), owed),
        firstDue: r.readNullable<String>('first_due'),
        onQist: capped(r.read<int>('on_qist'), owed),
        late: capped(r.read<int>('late'), owed),
      );
    }

    // The promises: each customer's latest, while it stands and is for a
    // day in the week, at what is still to come of it.
    final last = asOf.addDays(expectedCollectionDays - 1).value;
    final chased = await DriftUdhaarQueries(
      _db,
    ).dueParties(firmId, asOfDateLocal: asOf.value);
    for (final d in chased) {
      final promise = d.promise;
      if (promise == null || !promise.standingOn(asOf.value).isLive) continue;
      if (promise.promisedFor.compareTo(last) > 0) continue;
      final party = d.party;
      if (filters.partyId case final id? when id != party.id) continue;
      if (!_inGroup(party.group, filters.partyGroup)) continue;
      final said = promise.amount ?? party.balance;
      final rest = said - promise.paidSince;
      if (!rest.isPositive) continue;
      final promised = rest < party.balance ? rest : party.balance;
      final had = out[party.id];
      out[party.id] = ExpectedCollectionRow(
        partyId: party.id,
        name: party.name,
        phone: party.phone,
        fallsDue: had?.fallsDue ?? Money.zero,
        firstDue: had?.firstDue,
        onQist: had?.onQist ?? Money.zero,
        late: had?.late ?? Money.zero,
        promised: promised,
        promisedFor: promise.promisedFor,
      );
    }
    return out.values.toList();
  }

  static bool _inGroup(String? group, String? wanted) => switch (wanted) {
    null => true,
    ReportFilters.ungrouped => (group ?? '').trim().isEmpty,
    final g => (group ?? '').trim() == g.trim(),
  };
}
