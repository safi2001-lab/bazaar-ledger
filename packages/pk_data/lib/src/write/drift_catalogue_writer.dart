import 'package:pk_domain/pk_domain.dart';

import '../write/document_rows.dart';
import '../write/opening_entries.dart';
import '../write/sequence_allocator.dart';
import '../write/tx_runner.dart';

/// The settings key a party's note for the counter is kept under (M40).
///
/// Shared with the read side, which looks it up beside every party it
/// reads; two spellings of this key would be a note written and never seen.
const partyRemarksKeyPrefix = 'party.remarks.';

String partyRemarksKey(String partyId) => '$partyRemarksKeyPrefix$partyId';

/// The id of the settings row holding [partyId]'s note: derived, so every
/// counter writes the same row. See `DriftCatalogueWriter._keepRemarks`.
String partyRemarksRowId(String partyId) => 'remarks-$partyId';

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
      if (draft.packs case final packs? when packs.isNotEmpty) {
        await _keepPacks(tx, itemId, draft.name, draft.baseUnitId, packs);
      }

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
        await postOpeningStock(
          tx,
          itemId: itemId,
          itemName: draft.name,
          value: draft.openingRate.amountFor(draft.openingStock),
        );
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
        'SELECT name, sale_rate_milli_paisa, base_unit_id, negative_stock '
        'FROM items WHERE id = ? AND firm_id = ?',
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
      // Into the base unit the item already has, whatever the draft says:
      // the base unit is never edited (above), so neither is what a pack is
      // counted against.
      if (draft.packs case final packs?) {
        await _keepPacks(
          tx,
          itemId,
          draft.name,
          before.read<String>('base_unit_id'),
          packs,
        );
      }

      final oldRate = Rate.raw(before.read<int>('sale_rate_milli_paisa'));
      final oldRule = before.readNullable<String>('negative_stock');
      final newRule = draft.negativeStock?.code;
      tx.audit(
        action: 'ITEM_UPDATED',
        entityTable: 'items',
        entityId: itemId,
        summary: oldRate == draft.saleRate
            ? '${draft.name} edited'
            : '${draft.name} repriced from ${oldRate.amountOnly} to '
                  '${draft.saleRate.amountOnly}',
        // Who let an item sell below nothing, and when, is a question the
        // owner will ask (M53), so a change of rule is kept with the edit.
        before: {
          'name': before.read<String>('name'),
          'sale_rate_milli_paisa': oldRate.inMilliPaisa,
          if (oldRule != newRule) 'negative_stock': oldRule,
        },
        after: {
          'name': draft.name,
          'sale_rate_milli_paisa': draft.saleRate.inMilliPaisa,
          if (oldRule != newRule) 'negative_stock': newRule,
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
      final partyId = await tx.insert('parties', {
        ..._partyColumns(draft, actor),
        'party_group': await _groupAsKept(tx, draft.group),
      });
      await _keepRemarks(tx, partyId, draft.remarks);
      await postOpeningBalance(
        tx,
        partyId: partyId,
        partyName: draft.name,
        owed: draft.openingBalance,
      );
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
      // Their own current group is left out of the spelling lookup, or a
      // shopkeeper correcting "route 3" to "Route 3" on its only member
      // would be told the shop already spells it "route 3".
      columns['party_group'] = await _groupAsKept(
        tx,
        draft.group,
        excludingPartyId: partyId,
      );
      await tx.update('parties', partyId, columns);
      await _keepRemarks(tx, partyId, draft.remarks);
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
                         AND d.doc_type IN ('sale_invoice', 'other_income')
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
  Future<int> setPartyGroup(
    ActorContext actor,
    List<String> partyIds,
    String? group,
  ) => _runner.run(actor, (tx) async {
    final target = await _groupAsKept(tx, group);
    var moved = 0;
    for (final partyId in partyIds.toSet()) {
      final row = await tx.selectOne(
        'SELECT party_group FROM parties '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [partyId, actor.firmId],
      );
      if (row == null) {
        throw StateError('No customer $partyId in this shop.');
      }
      // Not written again when already there. A rewrite that changes
      // nothing still bumps the revision and travels to every counter, and
      // on the next sync it can overwrite a real change made over there.
      if (row.readNullable<String>('party_group') == target) continue;
      await tx.update('parties', partyId, {'party_group': target});
      moved++;
    }
    if (moved > 0) {
      tx.audit(
        action: 'PARTY_GROUP_SET',
        entityTable: 'parties',
        entityId: actor.firmId,
        summary: target == null
            ? '$moved taken out of their group'
            : '$moved put in $target',
      );
    }
    return moved;
  });

  @override
  Future<int> renamePartyGroup(
    ActorContext actor, {
    required String from,
    required String to,
  }) {
    final source = partyGroupName(from);
    final wanted = partyGroupName(to);
    if (source == null) {
      throw ArgumentError.value(from, 'from', 'which group is being renamed?');
    }
    if (wanted == null) {
      throw ArgumentError.value(to, 'to', 'a group needs a name');
    }
    return _runner.run(actor, (tx) async {
      // Hidden members too. A customer hidden for the season keeps their
      // route, and restoring them must not bring back a route the shop has
      // since renamed.
      final members = await tx.select(
        'SELECT id FROM parties '
        'WHERE firm_id = ? AND deleted_at_utc IS NULL AND party_group = ? '
        'ORDER BY id',
        [actor.firmId, source],
      );
      if (members.isEmpty) {
        throw StateError('Nobody is in $source, so there is nothing to move.');
      }
      // Another group already spelt this way, in any case, is a merge: the
      // members go into it under its own spelling, and the two are one.
      final other = await tx.selectOne(
        'SELECT party_group FROM parties '
        'WHERE firm_id = ? AND deleted_at_utc IS NULL '
        '  AND lower(party_group) = lower(?) AND party_group <> ? '
        'ORDER BY party_group = ? DESC, id LIMIT 1',
        [actor.firmId, wanted, source, wanted],
      );
      final target = other?.read<String>('party_group') ?? wanted;
      if (target == source) return 0;

      // Every member its own update, in this one transaction: each goes into
      // the outbox, so a counter on the shop's Wi-Fi receives every move, and
      // a failure on the thirtieth leaves all thirty where they were rather
      // than a route split between two names.
      for (final member in members) {
        await tx.update('parties', member.read<String>('id'), {
          'party_group': target,
        });
      }
      tx.audit(
        action: other == null ? 'PARTY_GROUP_RENAMED' : 'PARTY_GROUPS_MERGED',
        entityTable: 'parties',
        entityId: actor.firmId,
        summary: other == null
            ? '$source renamed to $target: ${members.length} moved'
            : '$source merged into $target: ${members.length} moved',
        before: {'party_group': source},
        after: {'party_group': target},
      );
      return members.length;
    });
  }

  @override
  Future<void> transferStock(ActorContext actor, StockTransferDraft draft) =>
      _runner.run(actor, (tx) async {
        final from = draft.from.trim();
        final to = draft.to.trim();
        if (!draft.qty.isPositive) {
          throw const StockRefused('Move something: the quantity is nothing.');
        }
        if (from.isEmpty || to.isEmpty || from == to) {
          throw const StockRefused(
            'Goods have to go from one place to another.',
          );
        }
        final item = await tx.selectOne(
          'SELECT name, track_stock, track_batch, track_serial, '
          '       avg_cost_milli_paisa FROM items '
          'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
          [draft.itemId, actor.firmId],
        );
        if (item == null || item.read<int>('track_stock') != 1) {
          throw const StockRefused('That item does not carry stock.');
        }
        final name = item.read<String>('name');
        final here = await tx.selectOne(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
          'FROM stock_ledger WHERE firm_id = ? AND item_id = ? '
          '  AND location_code = ? AND deleted_at_utc IS NULL',
          [actor.firmId, draft.itemId, from],
        );
        final onHand = Qty.raw(here?.read<int>('q') ?? 0);
        if (onHand < draft.qty) {
          throw StockRefused(
            'Only ${onHand.display} of $name is at $from, so '
            '${draft.qty.display} cannot be moved from there.',
          );
        }
        final byLot =
            item.read<int>('track_batch') == 1 ||
            item.read<int>('track_serial') == 1;
        final takes = byLot
            ? takeFefo(
                needed: draft.qty,
                lots: await lotBalancesAt(tx, draft.itemId, from),
                unlotted: await unlottedAt(tx, draft.itemId, from),
                today: actor.businessDate,
              )
            : <LotTake>[(lotId: null, qty: draft.qty)];
        final cost = Rate.raw(item.read<int>('avg_cost_milli_paisa'));
        for (final take in takes) {
          final value = cost.amountFor(take.qty);
          for (final (location, sign, type) in [
            (from, -1, 'transfer_out'),
            (to, 1, 'transfer_in'),
          ]) {
            await insertStockRow(
              tx,
              null,
              const {},
              StockMovementPosting(
                itemId: draft.itemId,
                txnType: type,
                qtyDelta: take.qty,
                rate: cost,
                valueDelta: value,
                occurredAtUtcMillis: actor.epochMillis,
                occurredOnLocal: actor.businessDate.value,
                lineNo: 0,
                locationCode: location,
              ),
              lotId: take.lotId,
              qtyDelta: sign < 0 ? -take.qty : take.qty,
              valueDelta: sign < 0 ? -value : value,
            );
          }
        }
        final note = draft.note?.trim();
        tx.audit(
          action: 'STOCK_TRANSFERRED',
          entityTable: 'items',
          entityId: draft.itemId,
          summary:
              '${draft.qty.display} of $name moved from $from to $to'
              '${note == null || note.isEmpty ? '' : ': $note'}',
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

    // M68: the body is [adjustStockOn], so a random stock check posts each
    // difference through this same path inside the check's own commit.
    return _runner.run(actor, (tx) => adjustStockOn(tx, draft));
  }

  /// Goods that left the shelf are an expense whether or not anyone noticed.
  ///
  /// Without this the Inventory account still carries stock that is not
  /// there, the Trial Balance is quietly wrong, and the shop's profit is
  /// overstated by exactly the value of what it lost.
  static Future<void> _postAdjustmentJournal(
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
    'name_search': nameSearchColumn(d.name),
    'code': _blank(d.code),
    'barcode': _blank(d.barcode),
    'category': _blank(d.category),
    'description': _blank(d.description),
    'base_unit_id': d.baseUnitId,
    'sale_rate_milli_paisa': d.saleRate.inMilliPaisa,
    'wholesale_rate_milli_paisa': d.wholesaleRate?.inMilliPaisa,
    'vip_rate_milli_paisa': d.vipRate?.inMilliPaisa,
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
    'track_batch': d.tracksBatch ? 1 : 0,
    'track_serial': d.tracksSerial ? 1 : 0,
    'is_active': d.isActive ? 1 : 0,
    // Null follows the shop's own rule (M53).
    'negative_stock': d.negativeStock?.code,
    // M59: how it is taxed. Left out when the form did not say, so an edit
    // from a form that does not show them leaves them as they were.
    if (d.isThirdSchedule case final third?) 'is_third_schedule': third ? 1 : 0,
    if (d.isService case final service?)
      'item_type': service ? 'service' : 'goods',
    // M49: what it is as a medicine, only when the form said; a form that
    // knows nothing of medicines leaves them as they are.
    if (d.medicine case final m?) ...medicineColumns(m),
    // M50: how long its warranty runs and whose it is, only when the form
    // said; none takes it off.
    if (d.warranty case final w?) ...{
      'warranty_months': w.isNone ? null : w.months,
      'warranty_kind': w.isNone ? null : w.kind.code,
    },
  };

  /// The item columns [details] is stored in (M49), the salt's search key
  /// worked out beside them so the two can never disagree. Blank is empty.
  static Map<String, Object?> medicineColumns(MedicineDetails details) {
    final m = details.tidied;
    return {
      'generic_name': m.genericName,
      'strength': m.strength,
      'generic_search': m.searchKey,
      'manufacturer': m.manufacturer,
      'schedule_class': m.schedule?.code,
    };
  }

  /// Makes [itemId]'s packs exactly [packs] (M53): each one its own
  /// conversion from the pack's unit into the item's [baseUnitId], at the
  /// pack's size.
  ///
  /// A pack still wanted at the same size is left alone, so a save that
  /// changes only the price writes nothing here and tells no counter that
  /// the carton changed. A new size is an update of the row the counters
  /// already have. A pack taken off is struck out, never destroyed, and one
  /// put back later is a new row: the unique index counts live rows only
  /// since v10, which is what lets a carton come off an item and go back on.
  ///
  /// Bills already written keep the size they were sold at — every line
  /// stores its own quantity in the base unit — so changing a carton from 24
  /// to 20 changes the next bill and no earlier one.
  static Future<void> _keepPacks(
    Tx tx,
    String itemId,
    String itemName,
    String baseUnitId,
    List<ItemPack> packs,
  ) async {
    final firmId = tx.actor.firmId;
    final shopEdges = [
      for (final r in await tx.select(
        'SELECT from_unit_id, to_unit_id, factor_thousandths '
        'FROM unit_conversions '
        'WHERE firm_id = ? AND item_id IS NULL AND deleted_at_utc IS NULL',
        [firmId],
      ))
        UnitEdge(
          fromUnitId: r.read<String>('from_unit_id'),
          toUnitId: r.read<String>('to_unit_id'),
          factorThousandths: r.read<int>('factor_thousandths'),
        ),
    ];
    final problem = packProblem(
      packs,
      baseUnitId: baseUnitId,
      shopUnits: UnitConverter(shopEdges),
    );
    if (problem != null) {
      throw ArgumentError.value(packs, 'packs', problem);
    }
    final live = {
      for (final r in await tx.select(
        'SELECT id, code FROM units '
        'WHERE firm_id = ? AND deleted_at_utc IS NULL',
        [firmId],
      ))
        r.read<String>('id'): r.read<String>('code'),
    };
    for (final pack in packs) {
      if (!live.containsKey(pack.unitId)) {
        throw StateError(
          'No unit ${pack.unitCode ?? pack.unitId} in this shop to pack '
          '$itemName in.',
        );
      }
    }

    final wanted = {for (final p in packs) p.unitId: p};
    final changes = <String>[];
    final held = await tx.select(
      'SELECT id, from_unit_id, factor_thousandths FROM unit_conversions '
      'WHERE firm_id = ? AND item_id = ? AND to_unit_id = ? '
      '  AND deleted_at_utc IS NULL '
      'ORDER BY id',
      [firmId, itemId, baseUnitId],
    );
    for (final row in held) {
      final unitId = row.read<String>('from_unit_id');
      final pack = wanted.remove(unitId);
      final code = live[unitId] ?? unitId;
      if (pack == null) {
        await tx.softDelete('unit_conversions', row.read<String>('id'));
        changes.add('$code taken off');
      } else if (pack.size.inThousandths !=
          row.read<int>('factor_thousandths')) {
        await tx.update('unit_conversions', row.read<String>('id'), {
          'factor_thousandths': pack.size.inThousandths,
        });
        changes.add('1 $code = ${pack.size.display}');
      }
    }
    for (final pack in wanted.values) {
      await tx.insert('unit_conversions', {
        'from_unit_id': pack.unitId,
        'to_unit_id': baseUnitId,
        'factor_thousandths': pack.size.inThousandths,
        'item_id': itemId,
      });
      changes.add('1 ${live[pack.unitId]} = ${pack.size.display}');
    }
    if (changes.isEmpty) return;
    tx.audit(
      action: 'ITEM_PACKS_SET',
      entityTable: 'items',
      entityId: itemId,
      summary:
          '$itemName packs, in ${live[baseUnitId] ?? 'its unit'}: '
          '${changes.join(', ')}',
    );
  }

  static Map<String, Object?> _partyColumns(PartyDraft d, ActorContext actor) =>
      {
        'name': d.name.trim(),
        'name_search': nameSearchColumn(d.name),
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
        'price_tier': d.priceTier.code,
        'default_discount_bp': d.defaultDiscountBp,
        'is_active': 1,
      };

  /// [raw] as it is kept: tidied, and spelt the way the shop already spells
  /// that group when one matches it in another case.
  ///
  /// "route 3" typed in a hurry joins "Route 3" rather than starting a second
  /// route with one customer on it, which would then be missing from every
  /// list and every report filtered by the real one. An exact match is
  /// preferred where both spellings already exist.
  static Future<String?> _groupAsKept(
    Tx tx,
    String? raw, {
    String? excludingPartyId,
  }) async {
    final tidy = partyGroupName(raw);
    if (tidy == null) return null;
    final kept = await tx.selectOne(
      'SELECT party_group FROM parties '
      'WHERE firm_id = ? AND deleted_at_utc IS NULL '
      '  AND lower(party_group) = lower(?) AND (? IS NULL OR id <> ?) '
      'ORDER BY party_group = ? DESC, id LIMIT 1',
      [tx.actor.firmId, tidy, excludingPartyId, excludingPartyId, tidy],
    );
    return kept?.read<String>('party_group') ?? tidy;
  }

  /// Keeps what the counter is told about a party, in the shop's settings.
  ///
  /// The parties table has no column for it and this milestone changes no
  /// schema, so the note is a settings row keyed by the party. Its id is
  /// derived from the party's, not a fresh ULID: two counters that each
  /// write the first note for the same customer while apart then write the
  /// same row, and the LAN merge keeps the later of the two by its clock —
  /// as it does for any other edit to a customer. Two fresh ids would have
  /// collided on the settings key instead, and one note would have arrived
  /// renamed as a clash.
  ///
  /// Never struck out: a note cleared is a row holding nothing, so the next
  /// note goes back into the same row rather than colliding with its own
  /// tombstone.
  static Future<void> _keepRemarks(
    Tx tx,
    String partyId,
    String? remarks,
  ) async {
    final text = remarks?.trim() ?? '';
    final rowId = partyRemarksRowId(partyId);
    final held = await tx.selectOne(
      'SELECT setting_value FROM settings WHERE id = ? AND firm_id = ?',
      [rowId, tx.actor.firmId],
    );
    if (held == null) {
      if (text.isEmpty) return;
      await tx.insert('settings', {
        'setting_key': partyRemarksKey(partyId),
        'setting_value': text,
        'value_type': 'string',
      }, id: rowId);
    } else if (held.read<String>('setting_value') != text) {
      await tx.update('settings', rowId, {'setting_value': text});
    }
  }

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
    if (d.defaultDiscountBp < 0 || d.defaultDiscountBp > 10000) {
      throw ArgumentError.value(
        d.defaultDiscountBp,
        'defaultDiscountBp',
        'a discount is between nothing and everything',
      );
    }
  }

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

/// Corrects the shelf inside [tx]: the stock correction [DriftCatalogueWriter.
/// adjustStock] makes, for a write that already has its transaction open
/// (M68: a random stock check posting its differences in one commit with the
/// check itself). The reason is required here as it is there.
Future<String> adjustStockOn(Tx tx, StockAdjustmentDraft draft) async {
  final actor = tx.actor;
  final reason = draft.reason.trim();
  if (reason.isEmpty) {
    throw ArgumentError.value(
      draft.reason,
      'reason',
      'a stock correction has to say why',
    );
  }
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
    await DriftCatalogueWriter._postAdjustmentJournal(
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
}
