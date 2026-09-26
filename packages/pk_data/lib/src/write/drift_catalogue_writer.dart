import 'package:pk_domain/pk_domain.dart';

import '../write/sequence_allocator.dart';
import '../write/tx_runner.dart';

/// The drift implementation of [CatalogueWriter].
///
/// Everything goes through [TxRunner], so an item added here appears in the
/// audit trail and the sync outbox without the caller having to remember.
final class DriftCatalogueWriter implements CatalogueWriter {
  const DriftCatalogueWriter(this._runner);

  final TxRunner _runner;

  @override
  Future<String> addItem(ActorContext actor, ItemDraft draft) {
    _validateItem(draft);
    return _runner.run(actor, (tx) async {
      await _assertItemCodeFree(tx, draft, null);

      final itemId = await tx.insert('items', _itemColumns(draft));

      // Opening stock is a stock-ledger row like any other, not a magic
      // column. A balance is a SUM over the ledger, so an opening quantity
      // that lived only on the item row would be invisible to every report
      // and to the reconciler.
      if (!draft.openingStock.isZero && draft.tracksStock) {
        await tx.insert('stock_ledger', {
          'item_id': itemId,
          'location_code': 'MAIN',
          'txn_type': 'opening',
          'qty_delta_thousandths': draft.openingStock.inThousandths,
          'rate_milli_paisa': draft.openingRate.inMilliPaisa,
          'value_delta_paisa': draft.openingRate
              .amountFor(draft.openingStock)
              .inPaisa,
          'balance_after_thousandths': draft.openingStock.inThousandths,
          'occurred_at_utc': actor.epochMillis,
          'occurred_on_local': actor.businessDate.value,
          'reason': 'Opening stock',
        });
      }

      tx.audit(
        action: 'ITEM_CREATED',
        entityTable: 'items',
        entityId: itemId,
        summary:
            '${draft.name} added at ${draft.saleRate.amountOnly} '
            'per unit',
      );
      return itemId;
    });
  }

  @override
  Future<void> updateItem(ActorContext actor, String itemId, ItemDraft draft) {
    _validateItem(draft);
    return _runner.run(actor, (tx) async {
      final before = await tx.selectOne(
        'SELECT name, sale_rate_milli_paisa FROM items '
        'WHERE id = ? AND firm_id = ?',
        [itemId, actor.firmId],
      );
      if (before == null) {
        throw StateError('No item $itemId in this shop.');
      }
      await _assertItemCodeFree(tx, draft, itemId);

      // Opening stock is deliberately not editable here. It is a posted
      // ledger row; changing it would rewrite history behind every report
      // that has already been printed. Correcting it is a stock adjustment,
      // which leaves a trail.
      final columns = _itemColumns(draft)
        ..remove('opening_stock_thousandths')
        ..remove('opening_rate_milli_paisa')
        // Cost is what was paid, not what an editor types. It moves when
        // goods are bought, and from M4 the purchase rule moves it.
        ..remove('avg_cost_milli_paisa')
        // Whether an item is on the counter is decided by archiveItem, not by
        // an editor that has no control for it. ItemDraft.isActive defaults to
        // true, so leaving it in meant correcting an archived item's price
        // silently put it back on sale.
        ..remove('is_active')
        // And the base unit is the unit every integer already written against
        // this item is counted in: `stock_ledger.qty_delta_thousandths` and
        // `document_lines.base_qty_thousandths` are both thousandths of it.
        // Editing the column reinterprets all of them at once, with no ledger
        // row and no conversion — twenty pieces of cooking oil become twenty
        // grams, and every posted invoice line for the item is redenominated
        // behind reports that have already been printed. Changing what an item
        // is measured in is a new item, or a conversion that leaves a trail.
        ..remove('base_unit_id');
      await tx.update('items', itemId, columns);

      final oldRate = Rate.raw(before.read<int>('sale_rate_milli_paisa'));
      tx.audit(
        action: 'ITEM_UPDATED',
        entityTable: 'items',
        entityId: itemId,
        summary: oldRate == draft.saleRate
            ? '${draft.name} edited'
            : '${draft.name} repriced from ${oldRate.amountOnly} to '
                  '${draft.saleRate.amountOnly}',
        before: {
          'name': before.read<String>('name'),
          'sale_rate_milli_paisa': oldRate.inMilliPaisa,
        },
        after: {
          'name': draft.name,
          'sale_rate_milli_paisa': draft.saleRate.inMilliPaisa,
        },
      );
    });
  }

  @override
  Future<void> archiveItem(ActorContext actor, String itemId) =>
      _runner.run(actor, (tx) async {
        await tx.update('items', itemId, {'is_active': 0});
        tx.audit(
          action: 'ITEM_ARCHIVED',
          entityTable: 'items',
          entityId: itemId,
          summary: 'Item hidden from the counter',
        );
      });

  @override
  Future<String> addParty(ActorContext actor, PartyDraft draft) {
    _validateParty(draft);
    return _runner.run(actor, (tx) async {
      final partyId = await tx.insert('parties', _partyColumns(draft, actor));
      tx.audit(
        action: 'PARTY_CREATED',
        entityTable: 'parties',
        entityId: partyId,
        summary: '${draft.name} added to the khata',
        amountPaisa: draft.openingBalance.isZero
            ? null
            : draft.openingBalance.inPaisa,
      );
      return partyId;
    });
  }

  @override
  Future<void> updateParty(
    ActorContext actor,
    String partyId,
    PartyDraft draft,
  ) {
    _validateParty(draft);
    return _runner.run(actor, (tx) async {
      // The opening balance is a starting fact, not an editable field: once
      // bills have been raised against it, changing it silently restates the
      // whole khata.
      final columns = _partyColumns(draft, actor)
        ..remove('opening_balance_paisa')
        ..remove('opening_balance_as_of_local')
        // Same reason the item path strips it, and this path was missed.
        // `_partyColumns` hardcodes `is_active: 1` — there is no field for it
        // on PartyDraft at all — so correcting an archived customer's phone
        // number put them back in the khata list, silently, without passing
        // the "nothing owed" guard archiveParty makes them pass. The audit row
        // said only "edited".
        ..remove('is_active');
      await tx.update('parties', partyId, columns);
      tx.audit(
        action: 'PARTY_UPDATED',
        entityTable: 'parties',
        entityId: partyId,
        summary: '${draft.name} edited',
      );
    });
  }

  @override
  Future<void> archiveParty(ActorContext actor, String partyId) =>
      _runner.run(actor, (tx) async {
        // The same arithmetic the khata list shows, opening balance included.
        // Summing only the documents told a shopkeeper that a customer
        // carrying Rs 5,000 of pre-app udhaar "owes 0", and hid the balance.
        //
        // And the two debts the first version did not know about: money the
        // shop is holding for them as an advance, and money the shop owes
        // them as a supplier. Hiding either is a liability that vanishes from
        // every screen while it is still real.
        final balance = await tx.selectOne(
          '''
          SELECT p.opening_balance_paisa
                   + COALESCE((
                       SELECT SUM(d.balance_paisa) FROM documents d
                       WHERE d.party_id = p.id
                         AND d.firm_id = p.firm_id
                         AND d.doc_type = 'sale_invoice'
                         AND d.status = 'posted'
                         AND d.deleted_at_utc IS NULL
                     ), 0) AS owed,
                 COALESCE((
                   SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                   FROM journal_lines jl
                   JOIN accounts a ON a.id = jl.account_id
                   WHERE jl.party_id = p.id
                     AND jl.firm_id = p.firm_id
                     AND a.system_key = 'customer_advances'
                     AND jl.deleted_at_utc IS NULL
                 ), 0) AS held,
                 COALESCE((
                   SELECT SUM(d.balance_paisa) FROM documents d
                   WHERE d.party_id = p.id
                     AND d.firm_id = p.firm_id
                     AND d.doc_type IN ('purchase_bill', 'expense')
                     AND d.status = 'posted'
                     AND d.deleted_at_utc IS NULL
                 ), 0) AS payable
          FROM parties p
          WHERE p.id = ? AND p.firm_id = ?
          ''',
          [partyId, actor.firmId],
        );
        final owed = Money.paisa(balance?.read<int>('owed') ?? 0);
        if (!owed.isZero) {
          throw StateError(
            'This customer still owes ${owed.amountOnly}. Settle or write off '
            'the udhaar before hiding them, or the balance disappears from '
            'the khata without ever being collected.',
          );
        }
        final held = Money.paisa(balance?.read<int>('held') ?? 0);
        if (!held.isZero) {
          throw StateError(
            'The shop is holding ${held.amountOnly} of their money as an '
            'advance. Give it back or use it on a bill before hiding them.',
          );
        }
        final payable = Money.paisa(balance?.read<int>('payable') ?? 0);
        if (!payable.isZero) {
          throw StateError(
            'The shop still owes them ${payable.amountOnly}. Pay it before '
            'hiding them, or the debt disappears from the khata unpaid.',
          );
        }
        await tx.update('parties', partyId, {'is_active': 0});
        tx.audit(
          action: 'PARTY_ARCHIVED',
          entityTable: 'parties',
          entityId: partyId,
          summary: 'Customer hidden',
        );
      });

  @override
  Future<void> restoreItem(ActorContext actor, String itemId) =>
      _runner.run(actor, (tx) async {
        await tx.update('items', itemId, {'is_active': 1});
        tx.audit(
          action: 'ITEM_RESTORED',
          entityTable: 'items',
          entityId: itemId,
          summary: 'Item back on the counter',
        );
      });

  @override
  Future<void> restoreParty(ActorContext actor, String partyId) =>
      _runner.run(actor, (tx) async {
        await tx.update('parties', partyId, {'is_active': 1});
        tx.audit(
          action: 'PARTY_RESTORED',
          entityTable: 'parties',
          entityId: partyId,
          summary: 'Back in the khata',
        );
      });

  @override
  Future<String> adjustStock(ActorContext actor, StockAdjustmentDraft draft) {
    final reason = draft.reason.trim();
    if (reason.isEmpty) {
      // Required, not optional. A stock figure that can be changed without
      // saying why is a stock figure nobody can defend — and "the numbers are
      // wrong and nobody knows why" is what makes a shopkeeper stop trusting
      // a system and go back to the register.
      throw ArgumentError.value(
        draft.reason,
        'reason',
        'a stock correction has to say why',
      );
    }

    return _runner.run(actor, (tx) async {
      final item = await tx.selectOne(
        'SELECT name, track_stock, avg_cost_milli_paisa FROM items '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [draft.itemId, actor.firmId],
      );
      if (item == null) {
        throw StateError('No item ${draft.itemId} in this shop.');
      }
      final itemName = item.read<String>('name');
      if (item.read<int>('track_stock') != 1) {
        throw StateError(
          '$itemName does not carry stock, so there is nothing to correct.',
        );
      }

      // Read inside the transaction, never from a figure the screen was
      // holding. Two counters correcting the same item at once would
      // otherwise both compute their difference from the same stale balance,
      // and the second would undo the first.
      final current = await tx.selectOne(
        'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
        'FROM stock_ledger '
        'WHERE firm_id = ? AND item_id = ? AND location_code = ? '
        '  AND deleted_at_utc IS NULL',
        [actor.firmId, draft.itemId, draft.locationCode],
      );
      final onHand = Qty.raw(current?.read<int>('q') ?? 0);

      final delta =
          draft.delta ??
          Qty.raw(draft.countedQty!.inThousandths - onHand.inThousandths);
      if (delta.isZero) {
        // A stock take that agrees with the ledger is not a correction, and
        // the schema refuses a zero movement anyway. Saying so is better than
        // writing a row that means nothing.
        throw StateError(
          '$itemName already reads ${onHand.display}. Nothing to correct.',
        );
      }

      final balanceAfter = onHand.inThousandths + delta.inThousandths;

      // Valued at what the goods cost, not at what they would have sold for.
      // A shop that loses a tin loses what it paid for the tin; the margin it
      // did not make is not an expense, it is a sale that never happened.
      final cost = Rate.raw(item.read<int>('avg_cost_milli_paisa'));
      final moved = Qty.raw(delta.inThousandths.abs());
      final value = cost.amountFor(moved);

      final ledgerId = await tx.insert('stock_ledger', {
        'item_id': draft.itemId,
        'location_code': draft.locationCode,
        // A recount that comes out short and a breakage are the same
        // arithmetic and different facts. The ledger says which it was.
        'txn_type': draft.isWriteOff ? 'wastage' : 'adjustment',
        'qty_delta_thousandths': delta.inThousandths,
        'rate_milli_paisa': cost.inMilliPaisa,
        'value_delta_paisa': delta.isNegative ? -value.inPaisa : value.inPaisa,
        'balance_after_thousandths': balanceAfter,
        'occurred_at_utc': actor.epochMillis,
        'occurred_on_local': actor.businessDate.value,
        'reason': reason,
      });

      if (!value.isZero) {
        await _postAdjustmentJournal(
          tx,
          actor,
          itemId: draft.itemId,
          itemName: itemName,
          value: value,
          isLoss: delta.isNegative,
          reason: reason,
        );
      }

      tx.audit(
        action: 'STOCK_ADJUSTED',
        entityTable: 'stock_ledger',
        entityId: ledgerId,
        summary:
            '$itemName: ${onHand.display} to '
            '${Qty.raw(balanceAfter).display} — $reason',
        amountPaisa: value.inPaisa,
      );
      return ledgerId;
    });
  }

  /// Goods that left the shelf are an expense whether or not anyone noticed.
  ///
  /// Without this the Inventory account still carries stock that is not
  /// there, the Trial Balance is quietly wrong, and the shop's profit is
  /// overstated by exactly the value of what it lost.
  Future<void> _postAdjustmentJournal(
    Tx tx,
    ActorContext actor, {
    required String itemId,
    required String itemName,
    required Money value,
    required bool isLoss,
    required String reason,
  }) async {
    final rows = await tx.select(
      'SELECT id, system_key FROM accounts '
      'WHERE firm_id = ? AND system_key IN (?, ?) '
      '  AND deleted_at_utc IS NULL AND is_active = 1',
      [actor.firmId, 'inventory', 'stock_wastage'],
    );
    final byKey = {
      for (final r in rows) r.read<String>('system_key'): r.read<String>('id'),
    };
    final inventory = byKey['inventory'];
    final wastage = byKey['stock_wastage'];
    if (inventory == null || wastage == null) {
      throw StateError(
        'The chart of accounts has no inventory or wastage account in firm '
        '${actor.firmId}, so a stock correction cannot be posted.',
      );
    }

    final entryId = await tx.insert('journal_entries', {
      'entry_no': (await const SequenceAllocator().allocate(
        tx,
        docType: 'journal_entry',
        fiscalYear: actor.businessDate.fiscalYear,
      )).formatted,
      'entry_date_utc': actor.epochMillis,
      'entry_date_local': actor.businessDate.value,
      'fiscal_year': actor.businessDate.fiscalYear,
      'source_type': 'adjustment',
      'narration': '$itemName — $reason',
      'total_debit_paisa': value.inPaisa,
      'total_credit_paisa': value.inPaisa,
    });

    // A loss expenses the wastage account and takes the goods off inventory.
    // A gain does the reverse: stock that turned out to be there was an
    // expense the shop had already written off.
    final lines = <(int, String, Money, Money)>[
      (1, isLoss ? wastage : inventory, value, Money.zero),
      (2, isLoss ? inventory : wastage, Money.zero, value),
    ];
    for (final line in lines) {
      await tx.insert('journal_lines', {
        'journal_entry_id': entryId,
        'line_no': line.$1,
        'account_id': line.$2,
        'debit_paisa': line.$3.inPaisa,
        'credit_paisa': line.$4.inPaisa,
        'item_id': itemId,
        'narration': reason,
      });
    }
  }

  /// The next journal number for this firm and fiscal year.
  // What used to be here, and why it is gone.
  //
  //   SELECT COALESCE(MAX(entry_no), 0) + 1 FROM journal_entries
  //   WHERE firm_id = ? AND fiscal_year = ?
  //
  // `entry_no` is TEXT. It holds a formatted number -- `JV-2627-0001` -- which
  // is what every other writer puts there, because a journal voucher number is
  // a document number a person reads and quotes, not a row counter.
  //
  // So that query did arithmetic on text. MAX over TEXT compares
  // lexicographically, which means after the ninth entry the maximum stays
  // '9' forever ('10' sorts below '9'), and the tenth stock correction of a
  // fiscal year failed with a raw UNIQUE constraint error from SQLite. In a
  // shop that had also posted a sale it was worse: MAX returns 'JV-2627-0001',
  // SQLite coerces that to 0 for the addition, and the FIRST correction tried
  // to write 1.
  //
  // Ten corrections in a year is an ordinary Tuesday. Nothing caught it
  // because no test made more than two.

  // -----------------------------------------------------------------------

  static Map<String, Object?> _itemColumns(ItemDraft d) => {
    'name': d.name.trim(),
    'name_search': d.searchKey,
    'code': _blank(d.code),
    'barcode': _blank(d.barcode),
    'category': _blank(d.category),
    'description': _blank(d.description),
    'base_unit_id': d.baseUnitId,
    'sale_rate_milli_paisa': d.saleRate.inMilliPaisa,
    'wholesale_rate_milli_paisa': d.wholesaleRate?.inMilliPaisa,
    'purchase_rate_milli_paisa': d.purchaseRate?.inMilliPaisa,
    'mrp_paisa': d.mrp?.inPaisa,
    'hs_code': _blank(d.hsCode),
    'min_stock_thousandths': d.minStock.inThousandths,
    'opening_stock_thousandths': d.openingStock.inThousandths,
    'opening_rate_milli_paisa': d.openingRate.inMilliPaisa,
    // The weighted average of one purchase is that purchase. Opening
    // stock is the shop's first consignment — the goods are already on
    // the shelf and the shopkeeper types what they cost — so the average
    // starts there and the M4 purchase rule moves it from there.
    //
    // Leaving it at the schema default meant `averageCostFor` returned
    // zero, the sale posted no COGS line, `documents.cost_paisa` was
    // stamped 0, and bill-wise profit reported the whole selling price as
    // margin: Rs 500 of profit on a tin bought for Rs 300. Every shop
    // hits this, because entering what is on the shelf is the last field
    // of the item quick-add form.
    'avg_cost_milli_paisa': d.openingStock.isZero
        ? 0
        : d.openingRate.inMilliPaisa,
    'track_stock': d.tracksStock ? 1 : 0,
    'is_active': d.isActive ? 1 : 0,
  };

  static Map<String, Object?> _partyColumns(PartyDraft d, ActorContext actor) =>
      {
        'name': d.name.trim(),
        'name_search': d.searchKey,
        'party_type': d.partyType,
        'phone': _blank(d.phone),
        'whatsapp': _blank(d.whatsapp),
        'address_line1': _blank(d.addressLine1),
        'city': _blank(d.city),
        'ntn': _blank(d.ntn),
        'strn': _blank(d.strn),
        'cnic': _blank(d.cnic),
        'buyer_registration_type': d.buyerRegistrationType,
        'is_on_atl': d.isOnAtl == null ? null : (d.isOnAtl! ? 1 : 0),
        'opening_balance_paisa': d.openingBalance.inPaisa,
        'opening_balance_as_of_local': actor.businessDate.value,
        'credit_limit_paisa': d.creditLimit?.inPaisa,
        'credit_days': d.creditDays,
        'is_active': 1,
      };

  static Future<void> _assertItemCodeFree(
    Tx tx,
    ItemDraft draft,
    String? excludingId,
  ) async {
    for (final (column, value) in [
      ('code', _blank(draft.code)),
      ('barcode', _blank(draft.barcode)),
    ]) {
      if (value == null) continue;
      final clash = await tx.selectOne(
        'SELECT id, name FROM items '
        'WHERE firm_id = ? AND $column = ? AND deleted_at_utc IS NULL '
        '  AND (? IS NULL OR id <> ?)',
        [tx.actor.firmId, value, excludingId, excludingId],
      );
      if (clash != null) {
        throw StateError(
          '${column == 'code' ? 'Code' : 'Barcode'} "$value" already belongs '
          'to ${clash.read<String>('name')}. Scanning it would ring up the '
          'wrong item.',
        );
      }
    }
  }

  static void _validateItem(ItemDraft d) {
    if (d.name.trim().isEmpty) {
      throw ArgumentError.value(d.name, 'name', 'an item needs a name');
    }
    if (d.saleRate.inMilliPaisa < 0) {
      throw ArgumentError.value(
        d.saleRate,
        'saleRate',
        'a price cannot be negative',
      );
    }
    if (d.openingStock.isNegative) {
      throw ArgumentError.value(
        d.openingStock,
        'openingStock',
        'opening stock cannot be negative',
      );
    }
  }

  static void _validateParty(PartyDraft d) {
    if (d.name.trim().isEmpty) {
      throw ArgumentError.value(d.name, 'name', 'a customer needs a name');
    }
    const allowed = {'customer', 'supplier', 'both'};
    if (!allowed.contains(d.partyType)) {
      throw ArgumentError.value(d.partyType, 'partyType', 'unknown type');
    }
  }

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}
