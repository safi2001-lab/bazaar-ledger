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
