import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The cash a van's sales took on one day: cash tenders against its sales.
/// ?1 firm, ?2 the van's location code, ?3 the business date.
const vanCashSql = '''
  SELECT COALESCE(SUM(pa.amount_paisa), 0) AS cash,
         COUNT(DISTINCT d.id) AS sales
  FROM documents d
  LEFT JOIN payment_allocations pa
    ON pa.document_id = d.id AND pa.deleted_at_utc IS NULL
    AND pa.payment_id IN (
      SELECT p.id FROM payments p
      WHERE p.firm_id = ?1 AND p.mode = 'cash' AND p.status <> 'void'
        AND p.deleted_at_utc IS NULL)
  WHERE d.firm_id = ?1 AND d.location_code = ?2 AND d.doc_date_local = ?3
    AND d.doc_type = 'sale_invoice' AND d.status = 'posted'
    AND d.deleted_at_utc IS NULL
''';

/// What is on a van now, by item. ?1 firm, ?2 the van's location code.
const vanStockSql = '''
  SELECT s.item_id, i.name, u.code AS unit_code,
         SUM(s.qty_delta_thousandths) AS q
  FROM stock_ledger s
  JOIN items i ON i.id = s.item_id
  JOIN units u ON u.id = i.base_unit_id
  WHERE s.firm_id = ?1 AND s.location_code = ?2 AND s.deleted_at_utc IS NULL
  GROUP BY s.item_id
  HAVING SUM(s.qty_delta_thousandths) > 0
  ORDER BY i.name COLLATE NOCASE
''';

/// Vans and their daily settlements, through the one write path (M18).
final class DriftVanWriter implements VanWriter {
  const DriftVanWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<String> addVan(
    ActorContext actor, {
    required String name,
    String? riderUserId,
  }) {
    final label = name.trim();
    if (label.isEmpty) throw const VanRefused('Give the van a name.');
    return runner.run(actor, (tx) async {
      final taken = {
        for (final r in await tx.select(
          'SELECT DISTINCT location_code FROM stock_ledger WHERE firm_id = ? '
          'UNION SELECT location_code FROM vans WHERE firm_id = ?',
          [actor.firmId, actor.firmId],
        ))
          r.read<String>('location_code'),
        'MAIN',
      };
      final id = await tx.insert('vans', {
        'name': label,
        'location_code': vanLocationCode(label, taken),
        'rider_user_id': riderUserId,
        'is_active': 1,
      });
      tx.audit(
        action: 'VAN_ADDED',
        entityTable: 'vans',
        entityId: id,
        summary: 'Van $label',
      );
      return id;
    });
  }

  @override
  Future<VanSettlementView> settle(
    ActorContext actor,
    String vanId, {
    required Money counted,
    bool returnStock = true,
  }) {
    if (counted.isNegative) {
      throw const VanRefused('Counted cash cannot be less than nothing.');
    }
    return runner.run(actor, (tx) async {
      final van = await tx.selectOne(
        'SELECT name, location_code FROM vans WHERE id = ? AND firm_id = ? '
        'AND deleted_at_utc IS NULL',
        [vanId, actor.firmId],
      );
      if (van == null) throw const VanRefused('That van is not kept.');
      final name = van.read<String>('name');
      final location = van.read<String>('location_code');
      final day = actor.businessDate.value;
      final done = await tx.selectOne(
        'SELECT 1 FROM van_settlements WHERE firm_id = ? AND van_id = ? '
        'AND settled_on_local = ? AND deleted_at_utc IS NULL',
        [actor.firmId, vanId, day],
      );
      if (done != null) {
        throw VanRefused('$name has already been settled today.');
      }

      final cash = await tx.selectOne(vanCashSql, [
        actor.firmId,
        location,
        day,
      ]);
      final expected = Money.paisa(cash?.read<int>('cash') ?? 0);

      // The rider's short or over, where the till's own is booked.
      String? journalId;
      final narration = 'Van $name settled for $day';
      final lines = settlementLines(
        expected: expected,
        counted: counted,
        narration: narration,
      );
      if (lines.isNotEmpty) {
        final number = await sequences.allocate(
          tx,
          docType: 'journal_entry',
          fiscalYear: actor.businessDate.fiscalYear,
        );
        final amount = (counted - expected).abs;
        journalId = await insertJournal(
          tx,
          null,
          JournalEntryPosting(
            entryNo: number.formatted,
            entryDateUtcMillis: actor.epochMillis,
            entryDateLocal: day,
            fiscalYear: actor.businessDate.fiscalYear,
            sourceType: 'adjustment',
            totalDebit: amount,
            totalCredit: amount,
            narration: narration,
            lines: lines,
          ),
        );
      }

      // What was not sold goes back to the shop floor, batch by batch.
      var returned = 0;
      if (returnStock) {
        for (final r in await tx.select(vanStockSql, [
          actor.firmId,
          location,
        ])) {
          final itemId = r.read<String>('item_id');
          final item = await tx.selectOne(
            'SELECT avg_cost_milli_paisa FROM items WHERE id = ?',
            [itemId],
          );
          final cost = Rate.raw(item?.read<int>('avg_cost_milli_paisa') ?? 0);
          final takes = <LotTake>[
            for (final lot in await lotBalancesAt(tx, itemId, location))
              if (lot.qty.isPositive) (lotId: lot.lotId, qty: lot.qty),
          ];
          final loose = await unlottedAt(tx, itemId, location);
          if (loose.isPositive) takes.add((lotId: null, qty: loose));
          for (final take in takes) {
            final value = cost.amountFor(take.qty);
            for (final (place, out, type) in [
              (location, true, 'transfer_out'),
              ('MAIN', false, 'transfer_in'),
            ]) {
              await insertStockRow(
                tx,
                null,
                const {},
                StockMovementPosting(
                  itemId: itemId,
                  txnType: type,
                  qtyDelta: take.qty,
                  rate: cost,
                  valueDelta: value,
                  occurredAtUtcMillis: actor.epochMillis,
                  occurredOnLocal: day,
                  lineNo: 0,
                  locationCode: place,
                ),
                lotId: take.lotId,
                qtyDelta: out ? -take.qty : take.qty,
                valueDelta: out ? -value : value,
              );
            }
          }
          returned++;
        }
      }

      final id = await tx.insert('van_settlements', {
        'van_id': vanId,
        'settled_on_local': day,
        'cash_expected_paisa': expected.inPaisa,
        'cash_counted_paisa': counted.inPaisa,
        'lines_returned_count': returned,
        'journal_entry_id': journalId,
      });
      final gap = counted - expected;
      tx.audit(
        action: 'VAN_SETTLED',
        entityTable: 'van_settlements',
        entityId: id,
        summary:
            '$narration: $expected expected, $counted counted'
            '${gap.isZero
                ? ''
                : gap.isNegative
                ? ', short ${gap.abs}'
                : ', over $gap'}',
        amountPaisa: counted.inPaisa,
      );
      return VanSettlementView(
        date: actor.businessDate,
        expected: expected,
        counted: counted,
        linesReturned: returned,
      );
    });
  }
}
