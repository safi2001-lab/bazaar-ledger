part of 'app_services.dart';

/// The writers, each checked against the shop's plan before it writes
/// (M21). Refusals happen here, below every screen, as permission ones do:
/// a button that forgot to check cannot get a paid feature past them.
///
/// Only starting something new of a paid kind is refused. An item that
/// already has a wholesale price can still be renamed on a free plan, and
/// a cheque already taken can still be cleared or bounced.

final class _PlanCatalogue implements CatalogueWriter {
  _PlanCatalogue(this._inner, this._app);

  final CatalogueWriter _inner;
  final AppServices _app;

  PlanServices get _plans => _app.plans;

  void _checkItem(ItemDraft draft, ItemSummary? before) {
    bool changed<T>(T now, T was) => now != was;
    final pricesNew =
        (draft.wholesaleRate != null &&
            changed(draft.wholesaleRate, before?.wholesaleRate)) ||
        (draft.vipRate != null && changed(draft.vipRate, before?.vipRate));
    if (pricesNew) _plans.require(PlanFeature.priceLists);
    final trackingNew =
        (draft.tracksBatch && !(before?.tracksBatch ?? false)) ||
        (draft.tracksSerial && !(before?.tracksSerial ?? false));
    if (trackingNew) _plans.require(PlanFeature.tracking);
    // The owner's call (M53): a cashier who could set an item to sell on
    // could talk past the one answer meant to stop him.
    if (draft.negativeStock != before?.negativeStock) {
      _app.require(Permission.settings);
    }
  }

  void _checkParty(PartyDraft draft, PriceTier? before) {
    if (draft.priceTier != PriceTier.retail && draft.priceTier != before) {
      _plans.require(PlanFeature.priceLists);
    }
  }

  @override
  Future<String> addItem(ActorContext actor, ItemDraft draft) async {
    _checkItem(draft, null);
    return _inner.addItem(actor, draft);
  }

  @override
  Future<void> updateItem(
    ActorContext actor,
    String itemId,
    ItemDraft draft,
  ) async {
    _checkItem(draft, await _app.queries.itemById(actor.firmId, itemId));
    return _inner.updateItem(actor, itemId, draft);
  }

  @override
  Future<void> archiveItem(ActorContext actor, String itemId) =>
      _inner.archiveItem(actor, itemId);

  @override
  Future<String> addParty(ActorContext actor, PartyDraft draft) async {
    _checkParty(draft, null);
    return _inner.addParty(actor, draft);
  }

  @override
  Future<void> updateParty(
    ActorContext actor,
    String partyId,
    PartyDraft draft,
  ) async {
    final before = await _app.queries.partyDraft(actor.firmId, partyId);
    _checkParty(draft, before?.priceTier);
    return _inner.updateParty(actor, partyId, draft);
  }

  @override
  Future<void> archiveParty(ActorContext actor, String partyId) =>
      _inner.archiveParty(actor, partyId);

  @override
  Future<void> restoreItem(ActorContext actor, String itemId) =>
      _inner.restoreItem(actor, itemId);

  @override
  Future<void> restoreParty(ActorContext actor, String partyId) =>
      _inner.restoreParty(actor, partyId);

  @override
  Future<String> adjustStock(ActorContext actor, StockAdjustmentDraft draft) =>
      _inner.adjustStock(actor, draft);

  @override
  Future<void> transferStock(
    ActorContext actor,
    StockTransferDraft draft,
  ) async {
    _plans.require(PlanFeature.godowns);
    return _inner.transferStock(actor, draft);
  }

  // Groups are free on every plan (M40): sorting a khata into routes is how
  // a shop keeps it at all, not an extra.
  @override
  Future<int> setPartyGroup(
    ActorContext actor,
    List<String> partyIds,
    String? group,
  ) => _inner.setPartyGroup(actor, partyIds, group);

  @override
  Future<int> renamePartyGroup(
    ActorContext actor, {
    required String from,
    required String to,
  }) => _inner.renamePartyGroup(actor, from: from, to: to);
}

/// Receipts and supplier payments: a new cheque needs a plan with cheques.
final class _PlanPayments implements PaymentWriter {
  _PlanPayments(this._inner, this._plans);

  final PaymentWriter _inner;
  final PlanServices _plans;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PaymentWriteContext write) body,
  ) => _inner.inTransaction(actor, (w) => body(_PlanPaymentContext(w, _plans)));
}

final class _PlanPaymentContext implements PaymentWriteContext {
  _PlanPaymentContext(this._inner, this._plans);

  final PaymentWriteContext _inner;
  final PlanServices _plans;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<List<OpenBill>> openBillsFor(String partyId) =>
      _inner.openBillsFor(partyId);

  @override
  Future<List<OpenBill>> openPayablesFor(String partyId) =>
      _inner.openPayablesFor(partyId);

  @override
  Future<String?> ledgerAccountFor(String paymentAccountId) =>
      _inner.ledgerAccountFor(paymentAccountId);

  @override
  Future<RecordedReceipt> apply(ReceiptPosting posting) async {
    if (posting.payment.isCheque) _plans.require(PlanFeature.cheques);
    return _inner.apply(posting);
  }
}

/// Corrections (M31): an edit that turns a cash receipt into a cheque is a
/// new cheque, and needs the plan a new cheque needs. Cancelling one never
/// does — a cheque already taken can always be put right.
final class _PlanCorrections implements CorrectionWriter {
  _PlanCorrections(this._inner, this._plans);

  final CorrectionWriter _inner;
  final PlanServices _plans;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CorrectionWriteContext write) body,
  ) => _inner.inTransaction(
    actor,
    (w) => body(
      _PlanCorrectionContext(w, _PlanPaymentContext(w.payments, _plans)),
    ),
  );
}

final class _PlanCorrectionContext implements CorrectionWriteContext {
  _PlanCorrectionContext(this._inner, this.payments);

  final CorrectionWriteContext _inner;

  @override
  final PaymentWriteContext payments;

  @override
  ActorContext get actor => _inner.actor;

  @override
  VoidWriteContext get documents => _inner.documents;

  @override
  ExpenseWriteContext get expenses => _inner.expenses;

  @override
  DebitNoteWriteContext get charges => _inner.charges;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<PostedPaymentSnapshot?> paymentSnapshot(String paymentId) =>
      _inner.paymentSnapshot(paymentId);

  @override
  Future<VoidedPayment> applyPaymentVoid(PaymentVoidPosting posting) =>
      _inner.applyPaymentVoid(posting);

  @override
  Future<OpeningSnapshot?> openingOf(String partyId) =>
      _inner.openingOf(partyId);

  @override
  Future<void> applyOpeningCorrection(OpeningCorrectionPosting posting) =>
      _inner.applyOpeningCorrection(posting);

  @override
  void recordCorrection(CorrectionRecord record) =>
      _inner.recordCorrection(record);
}

/// Sales: a cheque taken at the counter needs a plan with cheques.
final class _PlanSales implements SaleWriter {
  _PlanSales(this._inner, this._plans);

  final SaleWriter _inner;
  final PlanServices _plans;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(actor, (w) => body(_PlanSaleContext(w, _plans)));
}

final class _PlanSaleContext implements SaleWriteContext {
  _PlanSaleContext(this._inner, this._plans);

  final SaleWriteContext _inner;
  final PlanServices _plans;

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
    if (posting.payments.any((p) => p.isCheque)) {
      _plans.require(PlanFeature.cheques);
    }
    return _inner.apply(posting);
  }
}

/// Sales: a discount past what the signed-in role may give on its own is
/// refused (M22). Each role has carried its ceiling since M9; until now
/// nothing read it, and a cashier could knock any amount off a bill.
final class _CeilingSales implements SaleWriter {
  _CeilingSales(this._inner, this._app, {this.redeem}); // M66

  final SaleWriter _inner;
  final AppServices _app;

  /// M66: the customer's points this bill spends, checked and kept beneath
  /// this gate in the same commit (loyalty_services.dart).
  final LoyaltyRedemption? redeem;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(
    actor,
    (w) => body(_CeilingSaleContext(w, _app, redeem)), // M66
  );
}

final class _CeilingSaleContext implements SaleWriteContext {
  _CeilingSaleContext(this._inner, this._app, [this._redeem]); // M66

  final SaleWriteContext _inner;
  final AppServices _app;
  final LoyaltyRedemption? _redeem; // M66

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
    final role = _app.currentUser?.role ?? Role.owner;
    final discount = doc.lineDiscount + doc.billDiscount;
    var standing = 0;
    if (doc.partyId case final party?) {
      standing =
          (await _app.queries.partyDraft(
            actor.firmId,
            party,
          ))?.defaultDiscountBp ??
          0;
    }
    // M43: the shop's own schemes are the owner's word, as a standing
    // discount is. The bill slab's discount does not use up the cashier's
    // own ceiling; free goods past what the schemes give are the owner's
    // alone to hand over (scheme_services.dart).
    // M54: a bill made from challans gives free what they already sent free
    // — the goods left with the challan — and nothing past it.
    final sentFree = <String, Qty>{};
    for (final id in [?posting.convertedFromId, ...posting.alsoFromIds]) {
      for (final f in await _app.queries.challanBonusLines(actor.firmId, id)) {
        final item = f.itemId!;
        sentFree[item] = (sentFree[item] ?? Qty.zero) + f.baseQty;
      }
    }
    final schemes = await _app._schemesOn(posting, sentFree: sentFree);
    if (schemes.overGiven case final name? when role != Role.owner) {
      throw PermissionDenied(
        Permission.sell,
        '$name is going out free beyond what the shop\'s schemes give. Ask '
        'the owner to ring this one.',
      );
    }
    // M49: a pharmacy's "10% off on all medicines" is the owner's standing
    // discount, set in the shop's details, not the cashier's to have given.
    final pharmacy = await _app.pharmacy.rules();
    if (pharmacy.isPharmacy && pharmacy.offMrpBp > standing) {
      standing = pharmacy.offMrpBp;
    }
    // M66: a customer's points are spent at the owner's rate, within the
    // owner's share of a bill, as a slab is the owner's word: the discount
    // they make is not the cashier's to have given. Only the points on this
    // bill, of this bill's customer, inside its discount, and only because
    // the writer beneath checks them against the customer's points and
    // keeps them in this same commit, refusing the whole bill otherwise.
    final points = switch (_redeem) {
      final r? when r.partyId == doc.partyId && r.value <= doc.billDiscount =>
        r.value,
      _ => Money.zero,
    };
    if (!discountAllowed(
      role: role,
      subtotal: doc.subtotal,
      discount: discount - schemes.slab - points, // M66
      standingBp: standing,
    )) {
      final pct = role.maxDiscountBp / 100;
      throw PermissionDenied(
        Permission.sell,
        'A ${role.name} can take up to '
        '${pct == pct.roundToDouble() ? pct.toInt() : pct}% off a bill on '
        'their own. Ask the owner or a manager to ring this one.',
      );
    }
    return _inner.apply(posting);
  }
}
