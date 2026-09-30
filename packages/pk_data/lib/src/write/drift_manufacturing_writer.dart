import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// Recipes and production runs, through the one write path (M17).
final class DriftManufacturingWriter implements ManufacturingWriter {
  const DriftManufacturingWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<String> saveBom(
    ActorContext actor,
    BomDraft draft, {
    String? bomId,
  }) async {
    draft.check();
    return runner.run(actor, (tx) async {
      final output = await tx.selectOne(
        'SELECT track_stock FROM items WHERE id = ? AND firm_id = ? '
        'AND deleted_at_utc IS NULL',
        [draft.outputItemId, actor.firmId],
      );
      if (output == null || output.read<int>('track_stock') != 1) {
        throw const AssemblyRefused(
          'What a recipe makes has to be an item that carries stock.',
        );
      }
      final header = {
        'name': draft.name.trim(),
        'output_item_id': draft.outputItemId,
        'output_qty_thousandths': draft.outputQty.inThousandths,
        'overhead_paisa': draft.overhead.inPaisa,
      };
      final String id;
      if (bomId == null) {
        id = await tx.insert('boms', header);
      } else {
        id = bomId;
        await tx.update('boms', id, header);
        for (final old in await tx.select(
          'SELECT id FROM bom_lines WHERE bom_id = ? AND firm_id = ? '
          'AND deleted_at_utc IS NULL',
          [id, actor.firmId],
        )) {
          await tx.softDelete('bom_lines', old.read<String>('id'));
        }
      }
      for (final (i, line) in draft.lines.indexed) {
        await tx.insert('bom_lines', {
          'bom_id': id,
          'line_no': i + 1,
          'component_item_id': line.itemId,
          'qty_thousandths': line.qty.inThousandths,
        });
      }
      tx.audit(
        action: bomId == null ? 'BOM_CREATED' : 'BOM_UPDATED',
        entityTable: 'boms',
        entityId: id,
        summary: 'Recipe ${draft.name.trim()}',
      );
      return id;
    });
  }

  @override
  Future<AssemblyResult> assemble(
    ActorContext actor,
    String bomId,
    int runs,
  ) => runner.run(actor, (tx) async {
    final draft = await readBom(tx, bomId);
    if (draft == null) {
      throw const AssemblyRefused('That recipe is no longer kept.');
    }

    // Read inside the transaction: two counters making the same masala at
    // once must not both spend the same kilo of chilli.
    final ids = [draft.outputItemId, for (final l in draft.lines) l.itemId];
    final rows = await tx.select(
      '''
      SELECT i.id, i.name, i.avg_cost_milli_paisa, i.track_batch,
             i.track_serial, u.code AS unit_code,
             COALESCE((SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                       WHERE s.item_id = i.id AND s.firm_id = i.firm_id
                         AND s.location_code = 'MAIN'
                         AND s.deleted_at_utc IS NULL), 0) AS here,
             COALESCE((SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                       WHERE s.item_id = i.id AND s.firm_id = i.firm_id
                         AND s.deleted_at_utc IS NULL), 0) AS everywhere
      FROM items i JOIN units u ON u.id = i.base_unit_id
      WHERE i.firm_id = ? AND i.id IN (${List.filled(ids.length, '?').join(', ')})
      ''',
      [actor.firmId, ...ids],
    );
    final byId = {for (final r in rows) r.read<String>('id'): r};
    for (final r in rows) {
      if (r.read<int>('track_batch') == 1 || r.read<int>('track_serial') == 1) {
        throw AssemblyRefused(
          '${r.read<String>('name')} is kept by batch or serial, and a '
          'recipe cannot choose which batch to use yet.',
        );
      }
    }
    final out = byId[draft.outputItemId];
    if (out == null) {
      throw const AssemblyRefused('What this recipe makes is gone.');
    }
    final plan = planAssembly(
      bom: draft,
      runs: runs,
      components: {
        for (final l in draft.lines)
          if (byId[l.itemId] case final r?)
            l.itemId: ComponentOnHand(
              itemId: l.itemId,
              name: r.read<String>('name'),
              onHand: Qty.raw(r.read<int>('here')),
              avgCost: Rate.raw(r.read<int>('avg_cost_milli_paisa')),
              unitCode: r.read<String>('unit_code'),
            ),
      },
      output: CostPosition.onShelf(
        qty: Qty.raw(out.read<int>('everywhere')),
        avg: Rate.raw(out.read<int>('avg_cost_milli_paisa')),
      ),
    );

    final number = await sequences.allocate(
      tx,
      docType: 'assembly',
      fiscalYear: actor.businessDate.fiscalYear,
    );
    StockMovementPosting move(String itemId, String type, Qty qty, Rate r) =>
        StockMovementPosting(
          itemId: itemId,
          txnType: type,
          qtyDelta: qty,
          rate: r,
          valueDelta: Money.zero,
          occurredAtUtcMillis: actor.epochMillis,
          occurredOnLocal: actor.businessDate.value,
          lineNo: 0,
        );
    for (final use in plan.uses) {
      await insertStockRow(
        tx,
        null,
        const {},
        move(use.itemId, 'assembly_out', use.qty, use.cost),
        lotId: null,
        qtyDelta: -use.qty,
        valueDelta: -use.value,
      );
    }
    final unitCost = plan.outputQty.isPositive
        ? Rate.raw(
            (plan.totalCost.inPaisa * 1000000 +
                    plan.outputQty.inThousandths ~/ 2) ~/
                plan.outputQty.inThousandths,
          )
        : Rate.zero;
    await insertStockRow(
      tx,
      null,
      const {},
      move(draft.outputItemId, 'assembly_in', plan.outputQty, unitCost),
      lotId: null,
      qtyDelta: plan.outputQty,
      valueDelta: plan.totalCost,
    );
    await tx.update('items', draft.outputItemId, {
      'avg_cost_milli_paisa': plan.outputAvgAfter.inMilliPaisa,
    });

    // The components' value moved into the finished goods inside Inventory
    // and nets to nothing. Only the work is new value, and only it is
    // booked.
    String? journalId;
    if (plan.overhead.isPositive) {
      final entryNo = await sequences.allocate(
        tx,
        docType: 'journal_entry',
        fiscalYear: actor.businessDate.fiscalYear,
      );
      final narration =
          '${number.formatted}: ${draft.name} x$runs, work carried in stock';
      journalId = await insertJournal(
        tx,
        null,
        JournalEntryPosting(
          entryNo: entryNo.formatted,
          entryDateUtcMillis: actor.epochMillis,
          entryDateLocal: actor.businessDate.value,
          fiscalYear: actor.businessDate.fiscalYear,
          // A stock-side entry like a correction; the assembly row names it.
          sourceType: 'adjustment',
          totalDebit: plan.overhead,
          totalCredit: plan.overhead,
          narration: narration,
          lines: [
            JournalLinePosting(
              lineNo: 1,
              accountSystemKey: 'inventory',
              debit: plan.overhead,
              credit: Money.zero,
              itemId: draft.outputItemId,
              narration: narration,
            ),
            JournalLinePosting(
              lineNo: 2,
              accountSystemKey: 'production_overhead',
              debit: Money.zero,
              credit: plan.overhead,
              narration: narration,
            ),
          ],
        ),
      );
    }
    final id = await tx.insert('assemblies', {
      'bom_id': bomId,
      'assembly_no': number.formatted,
      'runs': runs,
      'output_item_id': draft.outputItemId,
      'output_qty_thousandths': plan.outputQty.inThousandths,
      'components_cost_paisa': plan.componentsCost.inPaisa,
      'overhead_paisa': plan.overhead.inPaisa,
      'journal_entry_id': journalId,
      'made_on_local': actor.businessDate.value,
    });
    tx.audit(
      action: 'ASSEMBLED',
      entityTable: 'assemblies',
      entityId: id,
      summary:
          '${number.formatted}: ${plan.outputQty.display} of '
          '${out.read<String>('name')} made',
      amountPaisa: plan.totalCost.inPaisa,
    );
    return AssemblyResult(assemblyNo: number.formatted, plan: plan);
  });
}

/// A recipe as it is kept, or null when it is gone.
Future<BomDraft?> readBom(Tx tx, String bomId) async {
  final head = await tx.selectOne(
    'SELECT name, output_item_id, output_qty_thousandths, overhead_paisa '
    'FROM boms WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
    [bomId, tx.actor.firmId],
  );
  if (head == null) return null;
  final lines = await tx.select(
    'SELECT component_item_id, qty_thousandths FROM bom_lines '
    'WHERE bom_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
    'ORDER BY line_no',
    [bomId, tx.actor.firmId],
  );
  return BomDraft(
    name: head.read<String>('name'),
    outputItemId: head.read<String>('output_item_id'),
    outputQty: Qty.raw(head.read<int>('output_qty_thousandths')),
    overhead: Money.paisa(head.read<int>('overhead_paisa')),
    lines: [
      for (final l in lines)
        BomLineDraft(
          itemId: l.read<String>('component_item_id'),
          qty: Qty.raw(l.read<int>('qty_thousandths')),
        ),
    ],
  );
}
