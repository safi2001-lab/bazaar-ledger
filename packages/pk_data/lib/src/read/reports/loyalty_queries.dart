part of '../drift_report_source.dart';

/// The reads behind the Loyalty report (M66), on the counter's own terms:
/// the bills are read by the one SQL the counter, the bill's paper and the
/// sale's own check read them by (`loyaltyBillsSql`, loyalty_reads.dart),
/// so the report cannot say a customer holds points the counter says they
/// do not.
mixin _LoyaltyQueries implements LoyaltyReportSource {
  AppDatabase get _db;

  @override
  Future<LoyaltyRules> loyaltyRules(String firmId) =>
      loyaltyRulesOf(_db, firmId);

  @override
  Future<List<LoyaltyCustomer>> loyaltyCustomers(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final narrow = StringBuffer();
    if (filters.partyId case final id?) {
      narrow.write(' AND d.party_id = ${q.text(id)}');
    }
    switch (filters.partyGroup) {
      case null:
        break;
      case ReportFilters.ungrouped:
        narrow.write(
          ' AND d.party_id IN (SELECT id FROM parties '
          "WHERE COALESCE(TRIM(party_group), '') = '')",
        );
      case final g:
        narrow.write(
          ' AND d.party_id IN (SELECT id FROM parties '
          'WHERE TRIM(party_group) = ${q.text(g.trim())})',
        );
    }
    final rows = await _db
        .customSelect(
          loyaltyBillsSql(narrow.toString()),
          variables: q.variables,
        )
        .get();
    final byParty = <String, List<LoyaltyBill>>{};
    for (final r in rows) {
      byParty
          .putIfAbsent(r.read<String>('party_id'), () => [])
          .add(loyaltyBillFrom(r));
    }
    if (byParty.isEmpty) return const [];
    // Every customer who has a sale bill, by a subquery rather than a list
    // of ids: a wholesaler's thousand customers are not a thousand bound
    // parameters.
    final parties = await _db
        .customSelect(
          'SELECT id, name, phone FROM parties WHERE firm_id = ?1 AND id IN '
          '(SELECT party_id FROM documents WHERE firm_id = ?1 '
          "AND doc_type = 'sale_invoice' AND party_id IS NOT NULL)",
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final p in parties)
        if (byParty.containsKey(p.read<String>('id')))
          LoyaltyCustomer(
            partyId: p.read<String>('id'),
            name: p.read<String>('name'),
            phone: p.readNullable<String>('phone'),
            bills: byParty[p.read<String>('id')] ?? const [],
          ),
    ];
  }
}
