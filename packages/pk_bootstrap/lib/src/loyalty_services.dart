part of 'app_services.dart';

/// Points that bring a customer back, a price list of their own, and the
/// profit on the bill while it is being made (M66).
///
/// ## Where they are kept
///
/// In the firm's `settings`, as JSON, as M43 keeps the schemes: one row for
/// the shop's loyalty rule (every version of it, [loyaltyRulesKey]), one row
/// per customer for their own prices ([partyPriceKeyPrefix]), one row per
/// bill that spent points ([loyaltyRedeemedKeyPrefix]), and the margin
/// switch. No schema change: nothing here is a figure the books join to.
/// What a customer EARNED is never stored at all — it is read off their
/// bills and the money against them every time (loyalty_reads.dart), so it
/// cannot disagree with the khata.
///
/// ## The points a bill spends, and the books
///
/// A redemption is a discount on the bill that uses the points: it goes
/// down M0's one bill-discount path, split across the lines to the paisa,
/// into Discount Given, on the day it is given. Points outstanding are a
/// promise kept beside the khata, not a liability in the books (loyalty.dart
/// says why). The bill's points are written in the bill's own commit
/// ([_LoyaltySaleWriter]), checked there against the customer's points as
/// the books stand inside that transaction, so two counters cannot both
/// spend the same points from one balance on one phone, and a bill killed
/// half way never spends points it did not take off.
///
/// ## Who may do what
///
/// The rule and the margin switch are the owner's (settings). A customer's
/// own prices are set by whoever may see what goods cost (M9's `seeCosts`:
/// the owner, a manager, the munshi), as a customer's price tier is on the
/// quick party sheet, and need the plan the other price lists need (M21).
/// Any cashier may use a customer's points at the counter, within the
/// shop's share of a bill: the rate and the share are the owner's word, so
/// the discount they make does not use up the cashier's own ceiling, as a
/// bill slab's does not (plan_gates.dart) — and the gate excuses exactly
/// the points this file then checks and writes, and nothing a cashier
/// typed. The margin is shown only to whoever may see costs.
final class LoyaltyServices {
  LoyaltyServices._(this._app);

  final AppServices _app;

  /// The settings key that turns the margin at the counter off.
  static const marginKey = 'margin.at_counter';

  String? get _firmId => _app._identity?.firmId;

  String get _today => BusinessDate.now(_app.clock).value;

  // -------------------------------------------------------------------------
  // The rule
  // -------------------------------------------------------------------------

  /// Whether whoever is signed in may change the shop's rule.
  bool get maySetRules => _app.can(Permission.settings);

  /// Every version of the shop's rule; none before the owner sets one.
  Future<LoyaltyRules> rules() async {
    final firmId = _firmId;
    if (firmId == null) return LoyaltyRules.none;
    return loyaltyRulesOf(_app.database, firmId);
  }

  /// The rule in force today, or null when the shop has never given points.
  Future<LoyaltyRule?> ruleToday() async => (await rules()).current;

  /// Keeps [rule] as the shop's from today: tomorrow's bills earn by it,
  /// and no point already earned changes. Refused with [LoyaltyRefused]
  /// when it does not make sense, before anything is written.
  Future<void> saveRule(LoyaltyRule rule) async {
    _app.require(Permission.settings);
    final actor = _app.actorNow();
    final checked = rule
        .copyWith(from: actor.businessDate.value, atUtc: actor.epochMillis)
        .checked();
    await _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, loyaltyRulesKey],
      );
      final before = held?.read<String>('setting_value');
      final after = LoyaltyRules.fromJson(before).withVersion(checked).toJson();
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': loyaltyRulesKey,
          'setting_value': after,
          'value_type': 'json',
        }, id: 'loyalty-rules-${actor.firmId}');
      } else if (before != after) {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': after,
        });
      } else {
        return;
      }
      tx.audit(
        action: 'LOYALTY_RULE_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: checked.isOn
            ? 'Loyalty from ${checked.from}: ${checked.earnPoints} points per '
                  'Rs ${checked.earnPer.amountOnly}, ${checked.redeemPoints} '
                  'points Rs ${checked.redeemValue.amountOnly}'
            : 'Loyalty points stopped from ${checked.from}',
        before: {'rules': before},
        after: {'rules': after},
      );
    });
  }

  // -------------------------------------------------------------------------
  // A customer's points
  // -------------------------------------------------------------------------

  /// [partyId]'s points as the books stand today.
  Future<LoyaltyStanding> standingOf(String partyId) async {
    final firmId = _firmId;
    if (firmId == null) return LoyaltyStanding.nothing;
    final rules = await this.rules();
    if (rules.isEmpty) return LoyaltyStanding.nothing;
    return loyaltyStanding(
      rules,
      await loyaltyBillsOf(_app.database, firmId, partyId),
      today: _today,
    );
  }

  /// The sale path for the bill on the counter: [redeem]'s points spent in
  /// the bill's own commit, and [recurring] moving its template on (M63),
  /// either or both. With neither, the ordinary sale path.
  PostSaleUseCase postSaleFor({
    RecurringMark? recurring,
    LoyaltyRedemption? redeem,
  }) {
    if (redeem == null || redeem.points <= 0) {
      return _app.recurring.postSaleFor(recurring);
    }
    return _app._postSaleThrough(
      _LoyaltySaleWriter(_app, redeem, recurring),
      redeem: redeem,
    );
  }

  // -------------------------------------------------------------------------
  // A customer's own prices
  // -------------------------------------------------------------------------

  /// Whether whoever is signed in may set a customer's own price.
  bool get maySetPrices => _app.can(Permission.seeCosts);

  /// [partyId]'s own prices; an empty list when they have none.
  Future<PartyPrices> pricesOf(String partyId) async {
    final firmId = _firmId;
    if (firmId == null) return PartyPrices(partyId: partyId);
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>('$partyPriceKeyPrefix$partyId'),
          ],
        )
        .getSingleOrNull();
    return PartyPrices.fromJson(partyId, row?.read<String>('setting_value'));
  }

  /// [partyId]'s own prices with the items they are for, by name — what
  /// their price list screen shows. An item hidden since is left out, and
  /// comes back with its price if the item does.
  Future<List<({ItemSummary item, Rate rate})>> priceListOf(
    String partyId,
  ) async {
    final firmId = _firmId;
    if (firmId == null) return const [];
    final prices = await pricesOf(partyId);
    final out = <({ItemSummary item, Rate rate})>[];
    for (final e in prices.rates.entries) {
      final item = await _app.queries.itemById(firmId, e.key);
      if (item != null) out.add((item: item, rate: e.value));
    }
    out.sort(
      (a, b) => a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
    );
    return out;
  }

  /// Keeps [rate] (per [itemId]'s own unit) as [partyId]'s own price for it,
  /// from the next line rung; null takes it off. Returns the list as kept.
  Future<PartyPrices> setPartyPrice(
    String partyId,
    String itemId,
    Rate? rate,
  ) async {
    _app.require(Permission.seeCosts);
    if (rate != null) _app.plans.require(PlanFeature.priceLists);
    if (rate != null && rate.inMilliPaisa <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be above nothing');
    }
    final actor = _app.actorNow();
    final key = '$partyPriceKeyPrefix$partyId';
    return _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, key],
      );
      final before = held?.read<String>('setting_value');
      final was = PartyPrices.fromJson(partyId, before);
      final now = was.withRate(itemId, rate);
      if (now == was) return was;
      final value = now.toJson();
      if (held == null) {
        // One row per customer, its id worked out from them, so the same
        // customer priced on two counters apart is one row the merge keeps
        // the later of, as M43's schemes are.
        await tx.insert('settings', {
          'setting_key': key,
          'setting_value': value,
          'value_type': 'json',
        }, id: 'party-prices-$partyId');
      } else {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': value,
        });
      }
      tx.audit(
        action: 'PARTY_PRICE_SET',
        entityTable: 'parties',
        entityId: partyId,
        summary: rate == null
            ? 'Own price taken off item $itemId'
            : 'Own price Rs ${rate.amountOnly} on item $itemId',
        before: {'prices': before},
        after: {'prices': value},
      );
      return now;
    });
  }

  // -------------------------------------------------------------------------
  // The margin at the counter
  // -------------------------------------------------------------------------

  /// Whether the counter shows the bill's profit: to whoever may see costs,
  /// unless the owner turned it off. False, without reading anything, for
  /// anybody else.
  Future<bool> marginShown() async {
    if (!_app.can(Permission.seeCosts)) return false;
    return await _marginSwitch() != 'off';
  }

  /// Whether the owner left the margin on, for the settings screen.
  Future<bool> marginSwitchedOn() async => await _marginSwitch() != 'off';

  Future<String?> _marginSwitch() async {
    final firmId = _firmId;
    if (firmId == null) return null;
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            const Variable<String>(marginKey),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('setting_value');
  }

  /// Turns the margin at the counter on or off, for every counter.
  Future<void> setMarginShown({required bool shown}) async {
    _app.require(Permission.settings);
    final actor = _app.actorNow();
    final value = shown ? 'on' : 'off';
    await _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings WHERE firm_id = ? '
        'AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, marginKey],
      );
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': marginKey,
          'setting_value': value,
        }, id: 'margin-at-counter-${actor.firmId}');
      } else if (held.read<String>('setting_value') != value) {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': value,
        });
      } else {
        return;
      }
      tx.audit(
        action: 'MARGIN_AT_COUNTER_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: shown
            ? 'The bill\'s profit is shown at the counter'
            : 'The bill\'s profit is not shown at the counter',
      );
    });
  }

  /// What each of [itemIds] costs, per its own unit, at the average the
  /// sale will post: refused, before anything is read, to a role that may
  /// not see costs. The counter asks once per change of the bill's items,
  /// never per keystroke.
  Future<Map<String, Rate>> counterCosts(Iterable<String> itemIds) async {
    _app.require(Permission.seeCosts);
    final firmId = _firmId;
    final ids = itemIds.toSet().toList();
    if (firmId == null || ids.isEmpty) return const {};
    final rows = await _app.database
        .customSelect(
          'SELECT id, avg_cost_milli_paisa FROM items WHERE firm_id = ? '
          'AND id IN (${List.filled(ids.length, '?').join(', ')})',
          variables: [
            Variable<String>(firmId),
            for (final id in ids) Variable<String>(id),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): Rate.raw(r.read<int>('avg_cost_milli_paisa')),
    };
  }
}

/// The sale writer for a bill that spends a customer's points (M66): the
/// ordinary drift sale — moving a repeating bill's template on when it is
/// one (M63) — and in the same commit the points checked and kept.
///
/// Checked inside the transaction, before the bill is written, against the
/// books as they stand there: the rule in force on the bill's day, the
/// points' worth at it, the shop's share of a bill, the customer's points,
/// and that the points are on this bill as part of its discount. Anything
/// wrong refuses the bill whole, in words, and nothing is written.
final class _LoyaltySaleWriter implements SaleWriter {
  _LoyaltySaleWriter(this._app, this._redeem, this._recurring);

  final AppServices _app;
  final LoyaltyRedemption _redeem;
  final RecurringMark? _recurring;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _app._runner.run(actor, (tx) {
    var inner = saleContextOn(tx);
    if (_recurring case final mark?) {
      inner = _RecurringSaleContext(tx, inner, mark, false);
    }
    return body(_LoyaltySaleContext(tx, inner, _redeem));
  });
}

final class _LoyaltySaleContext implements SaleWriteContext {
  _LoyaltySaleContext(this._tx, this._inner, this._redeem);

  final Tx _tx;
  final SaleWriteContext _inner;
  final LoyaltyRedemption _redeem;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      _inner.taxContextFor(partyId);

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) =>
      _inner.averageCostFor(itemIds);

  @override
  Future<Map<String, String>> ledgerAccountsFor(
    Iterable<String> paymentAccountIds,
  ) => _inner.ledgerAccountsFor(paymentAccountIds);

  @override
  Future<ChallanGoods?> deliveredOn(String documentId) =>
      _inner.deliveredOn(documentId);

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    final doc = posting.document;
    final partyId = doc.partyId;
    if (partyId == null || partyId != _redeem.partyId) {
      throw const LoyaltyRefused(LoyaltyProblem.noCustomer);
    }
    if (_redeem.points <= 0 || _redeem.value > doc.billDiscount) {
      throw const LoyaltyRefused(LoyaltyProblem.mismatch);
    }
    final held = await _tx.selectOne(
      'SELECT setting_value FROM settings WHERE firm_id = ? '
      'AND setting_key = ? AND deleted_at_utc IS NULL',
      [actor.firmId, loyaltyRulesKey],
    );
    final rules = LoyaltyRules.fromJson(held?.read<String>('setting_value'));
    final rule = rules.ruleAt(doc.docDateUtcMillis);
    if (rule == null || !rule.isOn) {
      throw const LoyaltyRefused(LoyaltyProblem.off);
    }
    if (rule.valueOf(_redeem.points) != _redeem.value) {
      throw const LoyaltyRefused(LoyaltyProblem.mismatch);
    }
    // The bill's goods after their own discounts and any other bill
    // discount (a slab, a figure typed): what the shop's share is of.
    final goods =
        doc.subtotal - doc.lineDiscount - (doc.billDiscount - _redeem.value);
    if (_redeem.value > rule.capOn(goods)) {
      throw const LoyaltyRefused(LoyaltyProblem.overCap);
    }
    final rows = await _tx.select(loyaltyBillsSql('AND d.party_id = ?2'), [
      actor.firmId,
      partyId,
    ]);
    final standing = loyaltyStanding(rules, [
      for (final r in rows) loyaltyBillFrom(r),
    ], today: doc.docDateLocal);
    if (standing.outstanding < _redeem.points) {
      throw const LoyaltyRefused(LoyaltyProblem.notEnough);
    }

    final posted = await _inner.apply(posting);
    await _tx.insert('settings', {
      'setting_key': '$loyaltyRedeemedKeyPrefix${posted.documentId}',
      'setting_value': _redeem.toJson(date: doc.docDateLocal),
      'value_type': 'json',
    }, id: 'loyalty-redeemed-${posted.documentId}');
    _tx.audit(
      action: 'LOYALTY_REDEEMED',
      entityTable: 'documents',
      entityId: posted.documentId,
      summary:
          '${posted.docNo}: ${_redeem.points} points used, '
          'Rs ${_redeem.value.amountOnly} off',
      amountPaisa: _redeem.value.inPaisa,
      after: _redeem.toMap(date: doc.docDateLocal),
    );
    return posted;
  }
}
