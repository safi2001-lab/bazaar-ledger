part of 'app_services.dart';

/// The shop's schemes (M43): each item's bonus and quantity slabs, and the
/// shop's own discount on a big bill.
///
/// ## Where they are kept
///
/// In the firm's `settings`, as JSON: one row per item under
/// [schemeItemKeyPrefix] and its id, and one row for the shop's bill slabs
/// under [schemeBillSlabsKey]. Not a schema change, and nothing a schema
/// change would buy: the counter reads them all at once, and the books never
/// join to them — a bill keeps what it was sold at on its own lines, so a
/// scheme changed tomorrow changes tomorrow's bills and no earlier one.
///
/// One row per item so two counters each changing a different item's
/// scheme while apart both keep theirs when they meet (M41's shortage list
/// does the same), and each row's id is worked out from what it is for
/// rather than drawn fresh, so an owner who sets one item's scheme on two
/// phones apart writes one row twice and the merge keeps the later, as it
/// does any edit (M53's rule does the same). A scheme taken off is kept as
/// an empty one rather than struck out: a struck-out settings row holds its
/// key for ever, and the scheme could never go back on.
///
/// ## Who may do what
///
/// Everybody's counter applies them; only whoever may change the shop's
/// settings — the owner — may change them. They are the owner's word on
/// what the shop gives away, which is exactly why a cashier ringing them is
/// not spending their own discount ceiling (plan_gates.dart).
extension SchemeServices on AppServices {
  /// Whether whoever is signed in may change a scheme.
  bool get canSetSchemes => can(Permission.settings);

  /// The shop's schemes, worked into the shelf's terms: each bonus in the
  /// item's own unit, with the goods it gives named, and every slab.
  ///
  /// A bonus whose units no longer convert (a carton taken off the item)
  /// or whose free item is gone is left out rather than guessed at: a
  /// scheme that cannot be worked out exactly is one the counter does not
  /// give, and the owner sees it still listed in Settings to put right.
  Future<SchemeBook> schemeBook() async {
    final firmId = _identity?.firmId;
    if (firmId == null) return SchemeBook.empty;
    final rows = await _schemeRows(firmId);

    final schemes = <ItemScheme>[];
    var billSlabs = const <BillSlab>[];
    for (final (key, value) in rows) {
      if (key == schemeBillSlabsKey) {
        billSlabs = BillSlab.listFromJson(value);
      } else if (key.startsWith(schemeItemKeyPrefix)) {
        final scheme = ItemScheme.fromJson(
          key.substring(schemeItemKeyPrefix.length),
          value,
        );
        if (!scheme.isEmpty) schemes.add(scheme);
      }
    }

    final slabs = <String, List<QtySlab>>{
      for (final s in schemes)
        if (s.slabs.isNotEmpty) s.itemId: s.slabs,
    };

    final bonuses = <String, BonusOffer>{};
    final withBonus = [
      for (final s in schemes)
        if (s.bonus != null) s,
    ];
    if (withBonus.isNotEmpty) {
      final units = {for (final u in await queries.units(firmId)) u.id: u.code};
      final converter = UnitConverter(await queries.unitConversions(firmId));
      for (final s in withBonus) {
        final offer = await _offerFor(firmId, s, units, converter);
        if (offer != null) bonuses[s.itemId] = offer;
      }
    }
    return SchemeBook(bonuses: bonuses, slabs: slabs, billSlabs: billSlabs);
  }

  Future<BonusOffer?> _offerFor(
    String firmId,
    ItemScheme scheme,
    Map<String, String> unitCodes,
    UnitConverter converter,
  ) async {
    final rule = scheme.bonus!;
    final item = await queries.itemById(firmId, scheme.itemId);
    // A serial piece is a phone with its own number: nothing can hand one
    // over free without somebody choosing which.
    if (item == null || item.tracksSerial) return null;
    try {
      Qty inBase(Qty qty) => rule.unitId == null || rule.unitId == item.unitId
          ? qty
          : converter.convert(
              qty,
              fromUnitId: rule.unitId!,
              toUnitId: item.unitId,
              itemId: item.id,
            );
      final buyBase = inBase(rule.buy);
      if (rule.isSameItem) {
        final unitId = rule.unitId ?? item.unitId;
        return BonusOffer(
          rule: rule,
          buyBase: buyBase,
          freeBase: inBase(rule.free),
          freeItemId: item.id,
          freeItemName: item.name,
          freeUnitId: unitId,
          freeUnitCode: unitCodes[unitId] ?? item.unitCode,
          freeItemCode: item.code,
          freeHsCode: item.hsCode,
          freeTracksStock: item.tracksStock,
        );
      }
      final other = await queries.itemById(firmId, rule.freeItemId!);
      if (other == null || other.tracksSerial) return null;
      return BonusOffer(
        rule: rule,
        buyBase: buyBase,
        freeBase: rule.free,
        freeItemId: other.id,
        freeItemName: other.name,
        freeUnitId: other.unitId,
        freeUnitCode: other.unitCode,
        freeItemCode: other.code,
        freeHsCode: other.hsCode,
        freeTracksStock: other.tracksStock,
      );
    } on UnitConversionException {
      return null;
    }
  }

  /// [itemId]'s own scheme as the owner typed it; an empty one when it has
  /// none.
  Future<ItemScheme> itemScheme(String itemId) async {
    final firmId = _identity?.firmId;
    if (firmId == null) return ItemScheme(itemId: itemId);
    final row = await database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>('$schemeItemKeyPrefix$itemId'),
          ],
        )
        .getSingleOrNull();
    return ItemScheme.fromJson(itemId, row?.read<String>('setting_value'));
  }

  /// The shop's bill slabs, smallest first.
  Future<List<BillSlab>> billSlabs() async {
    final firmId = _identity?.firmId;
    if (firmId == null) return const [];
    final row = await database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            const Variable<String>(schemeBillSlabsKey),
          ],
        )
        .getSingleOrNull();
    return BillSlab.listFromJson(row?.read<String>('setting_value'));
  }

  /// Every item that has a scheme, with it, by name — what Settings lists.
  Future<List<({ItemSummary item, ItemScheme scheme})>>
  itemsWithSchemes() async {
    final firmId = _identity?.firmId;
    if (firmId == null) return const [];
    final out = <({ItemSummary item, ItemScheme scheme})>[];
    for (final (key, value) in await _schemeRows(firmId)) {
      if (!key.startsWith(schemeItemKeyPrefix)) continue;
      final scheme = ItemScheme.fromJson(
        key.substring(schemeItemKeyPrefix.length),
        value,
      );
      if (scheme.isEmpty) continue;
      final item = await queries.itemById(firmId, scheme.itemId);
      if (item != null) out.add((item: item, scheme: scheme));
    }
    out.sort(
      (a, b) => a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
    );
    return out;
  }

  /// Keeps [scheme] as its item's, from the next bill. An empty one takes
  /// the item's scheme off. Refused with [SchemeRefused] when it does not
  /// make sense, before anything is written.
  Future<void> saveItemScheme(ItemScheme scheme) async {
    require(Permission.settings);
    final checked = scheme.checked();
    final actor = actorNow();
    await _putSetting(
      actor,
      key: checked.settingKey,
      id: 'scheme-${checked.itemId}',
      value: checked.toJson(),
      action: 'SCHEME_SET',
      entityTable: 'items',
      entityId: checked.itemId,
      summary: _describe(checked),
    );
  }

  /// Keeps [slabs] as the shop's discounts on a big bill, from the next
  /// bill. An empty list takes them off.
  Future<void> saveBillSlabs(List<BillSlab> slabs) async {
    require(Permission.settings);
    final checked = BillSlab.checked(slabs);
    final actor = actorNow();
    await _putSetting(
      actor,
      key: schemeBillSlabsKey,
      id: 'scheme-bill-${actor.firmId}',
      value: BillSlab.listToJson(checked),
      action: 'BILL_SLABS_SET',
      entityTable: 'settings',
      entityId: actor.firmId,
      summary: checked.isEmpty
          ? 'No discount on a big bill'
          : 'Bill discounts: ${checked.map(_slabWords).join(', ')}',
    );
  }

  static String _slabWords(BillSlab s) =>
      '${s.from.amountOnly}+ ${s.percentLabel}';

  Future<void> _putSetting(
    ActorContext actor, {
    required String key,
    required String id,
    required String value,
    required String action,
    required String entityTable,
    required String entityId,
    required String summary,
  }) => _runner.run(actor, (tx) async {
    final held = await tx.selectOne(
      'SELECT id, setting_value FROM settings WHERE firm_id = ? '
      'AND setting_key = ? AND deleted_at_utc IS NULL',
      [actor.firmId, key],
    );
    final before = held?.read<String>('setting_value');
    if (held == null) {
      await tx.insert('settings', {
        'setting_key': key,
        'setting_value': value,
        'value_type': 'json',
      }, id: id);
    } else if (before != value) {
      await tx.update('settings', held.read<String>('id'), {
        'setting_value': value,
      });
    } else {
      return;
    }
    tx.audit(
      action: action,
      entityTable: entityTable,
      entityId: entityId,
      summary: summary,
      before: {'scheme': before},
      after: {'scheme': value},
    );
  });

  static String _describe(ItemScheme s) {
    if (s.isEmpty) return 'Scheme taken off';
    final parts = [
      if (s.bonus case final b?) 'bonus ${b.label}',
      for (final slab in s.slabs)
        '${slab.from.display}+ at ${slab.rate.amountOnly}',
    ];
    return 'Scheme: ${parts.join(', ')}';
  }

  Future<List<(String, String)>> _schemeRows(String firmId) async {
    final rows = await database
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          "WHERE firm_id = ? AND setting_key LIKE 'scheme.%' "
          'AND deleted_at_utc IS NULL ORDER BY setting_key',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        (r.read<String>('setting_key'), r.read<String>('setting_value')),
    ];
  }

  /// What the shop's schemes allow on [posting], for the discount ceiling
  /// (plan_gates.dart): the bill slab's discount, which the owner gave and
  /// a cashier may ring, and any free goods past what the schemes give,
  /// which only the owner may hand over.
  ///
  /// [sentFree] is what challans this bill is made from sent free (M54):
  /// that much of each item was handed over already, under the schemes of
  /// that day, and the bill only puts it on paper.
  Future<({Money slab, String? overGiven})> _schemesOn(
    SalePosting posting, {
    Map<String, Qty> sentFree = const {},
  }) async {
    final hasFree = posting.lines.any((l) => l.isFreeItem);
    if (!hasFree && !posting.document.billDiscount.isPositive) {
      return (slab: Money.zero, overGiven: null);
    }
    final book = await schemeBook();
    final doc = posting.document;
    final slab =
        book.billSlabFor(doc.subtotal - doc.lineDiscount)?.discount ??
        Money.zero;
    if (!hasFree) return (slab: slab, overGiven: null);

    final paid = <String, Qty>{};
    final free = <String, (String, Qty)>{};
    for (final l in posting.lines) {
      final id = l.itemId;
      if (id == null) continue;
      if (l.isFreeItem) {
        final had = free[id]?.$2 ?? Qty.zero;
        free[id] = (l.itemNameSnapshot, had + l.baseQty);
      } else {
        paid[id] = (paid[id] ?? Qty.zero) + l.baseQty;
      }
    }
    final allowed = book.freeAllowed(paid);
    for (final MapEntry(key: id, value: (name, qty)) in free.entries) {
      final schemes = allowed[id] ?? Qty.zero;
      final sent = sentFree[id] ?? Qty.zero; // M54
      if (qty > (sent > schemes ? sent : schemes)) {
        return (slab: slab, overGiven: name);
      }
    }
    return (slab: slab, overGiven: null);
  }
}
