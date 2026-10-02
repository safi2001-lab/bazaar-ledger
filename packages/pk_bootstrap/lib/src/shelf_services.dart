part of 'app_services.dart';

/// Never sold into thin air (M53): the shop's rule for selling below
/// nothing, and the shelf as the counter is about to sell from it.
///
/// ## Who may do what
///
/// Anybody at the counter is asked, or refused; only whoever may change the
/// shop's settings — the owner — may change the rule, the shop's or an
/// item's. A cashier who could set an item to sell on could talk past the
/// one answer the owner chose so that nobody could.
///
/// ## Two counters, one last packet
///
/// The rule is kept on each phone at the moment of sale. Two counters on the
/// shop's Wi-Fi that are apart — the router off, a van out of range — can
/// each sell the last packet, each correctly by what it knows. When they
/// meet, the merge keeps both bills (a sale is never merged away), the shelf
/// reads one below nothing, and the item list and the low-stock list show it
/// in red until somebody counts the shelf. Refusing the second sale after
/// the fact would mean unwriting a bill a customer already holds.
final class ShelfServices {
  ShelfServices._(this._app);

  final AppServices _app;

  DriftShelfReader get _reader => DriftShelfReader(_app.database);

  /// The shop's own rule, or what a shop that never chose gets.
  Future<NegativeStock> shopRule() async {
    final id = _app._identity;
    if (id == null) return NegativeStock.shopDefault;
    return _reader.shopRule(id.firmId);
  }

  /// Whether whoever is signed in may change a rule, the shop's or an
  /// item's.
  bool get canSetRules => _app.can(Permission.settings);

  /// Sets the shop's own rule. Every item that has none of its own follows
  /// it from the next sale.
  Future<void> setShopRule(NegativeStock rule) async {
    _app.require(Permission.settings);
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings '
        'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, negativeStockSettingKey],
      );
      if (held == null) {
        // An id worked out from the shop's, not a fresh one: an owner who
        // sets the rule on two phones while they are apart writes one row
        // twice, and the merge keeps the later, as it does any edit. Two
        // fresh ids would clash on the key and one rule would arrive
        // renamed.
        await tx.insert('settings', {
          'setting_key': negativeStockSettingKey,
          'setting_value': rule.code,
        }, id: 'shelf-rule-${actor.firmId}');
      } else if (held.read<String>('setting_value') != rule.code) {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': rule.code,
        });
      } else {
        return;
      }
      tx.audit(
        action: 'NEGATIVE_STOCK_RULE_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: 'Selling below nothing: ${rule.code} for the whole shop',
        before: {'rule': held?.read<String>('setting_value')},
        after: {'rule': rule.code},
      );
    });
  }

  /// The shelf for [itemIds] where this phone sells from: the shop floor,
  /// or the van its rider is out with (M18) — or at [locationCode] when it
  /// is given, as a challan's shop floor is.
  ///
  /// What the counter asks with, read through the same reader the sale
  /// path refuses with, so the two cannot disagree about the figure.
  Future<Map<String, ShelfState>> atCounter(
    Iterable<String> itemIds, {
    String? locationCode,
  }) async {
    final ids = itemIds.toSet();
    if (ids.isEmpty || _app._identity == null) return const {};
    return _reader.shelfFor(
      _app.actorNow(),
      ids,
      locationCode: locationCode ?? await _app.counterLocation(),
    );
  }

  /// Whether any of [documentIds] is a delivery challan: a bill made from
  /// one moves no stock, so the shelf has nothing to say about it.
  Future<bool> anyChallan(Iterable<String> documentIds) async {
    final ids = documentIds.toSet().toList();
    final id = _app._identity;
    if (ids.isEmpty || id == null) return false;
    final row = await _app.database
        .customSelect(
          'SELECT COUNT(*) AS n FROM documents '
          "WHERE firm_id = ? AND doc_type = 'delivery_challan' "
          'AND id IN (${List.filled(ids.length, '?').join(', ')})',
          variables: [
            Variable<String>(id.firmId),
            for (final d in ids) Variable<String>(d),
          ],
        )
        .getSingle();
    return row.read<int>('n') > 0;
  }
}
