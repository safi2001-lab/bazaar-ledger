import 'package:pk_domain/pk_domain.dart';

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
          'value_delta_paisa':
              draft.openingRate.amountFor(draft.openingStock).inPaisa,
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
        summary: '${draft.name} added at ${draft.saleRate.amountOnly} '
            'per unit',
      );
      return itemId;
    });
  }

  @override
  Future<void> updateItem(
    ActorContext actor,
    String itemId,
    ItemDraft draft,
  ) {
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
        ..remove('opening_rate_milli_paisa');
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
        ..remove('opening_balance_as_of_local');
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
        final balance = await tx.selectOne(
          '''
          SELECT COALESCE(SUM(balance_paisa), 0) AS owed
          FROM documents
          WHERE party_id = ? AND status = 'posted' AND deleted_at_utc IS NULL
          ''',
          [partyId],
        );
        final owed = Money.paisa(balance?.read<int>('owed') ?? 0);
        if (!owed.isZero) {
          throw StateError(
            'This customer still owes ${owed.amountOnly}. Settle or write off '
            'the udhaar before hiding them, or the balance disappears from '
            'the khata without ever being collected.',
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
        'track_stock': d.tracksStock ? 1 : 0,
        'is_active': d.isActive ? 1 : 0,
      };

  static Map<String, Object?> _partyColumns(
    PartyDraft d,
    ActorContext actor,
  ) =>
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
