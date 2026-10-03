part of 'app_services.dart';

/// Pakistan's rules kept at the counter (M59): the province's tax on the
/// shop's services, and the buyer's name on a big bill.
///
/// The Third Schedule's printed price and FBR's offline mode need nothing
/// kept here: the first is the item's own MRP and flag, the second is
/// [FbrServices]'s queue.
final class CounterTaxServices {
  CounterTaxServices._(this._app);

  final AppServices _app;

  /// The province's tax on the shop's services, or null for none.
  Future<ServiceTaxSetting?> serviceTax() async {
    final id = _app._identity;
    if (id == null) return null;
    final row = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            Variable<String>(serviceTaxSettingKey),
          ],
        )
        .getSingleOrNull();
    return ServiceTaxSetting.decode(row?.read<String>('setting_value'));
  }

  /// Whether whoever is signed in may set it: the owner, as every other
  /// tax setting.
  bool get canSet => _app.can(Permission.settings);

  /// Sets who taxes the shop's services and at what rates; null for none.
  ///
  /// A settings row, so it travels to the shop's other counters with the
  /// rest of the settings and is in every backup, and every change is in
  /// the audit log with what it was before. The id is worked out from the
  /// shop's, as the shelf rule's is (M53): an owner who sets it on two
  /// phones while they are apart writes one row twice, and the merge keeps
  /// the later.
  Future<void> setServiceTax(ServiceTaxSetting? setting) async {
    _app.require(Permission.settings);
    if (setting != null &&
        (!ServiceTaxSetting.validRateBp(setting.standardBp) ||
            !ServiceTaxSetting.validRateBp(setting.digitalBp))) {
      throw ArgumentError.value(
        setting.encode(),
        'setting',
        'a provincial rate is between 0% and 50%',
      );
    }
    final value = setting?.encode() ?? 'none';
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings '
        'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, serviceTaxSettingKey],
      );
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': serviceTaxSettingKey,
          'setting_value': value,
        }, id: 'service-tax-${actor.firmId}');
      } else if (held.read<String>('setting_value') != value) {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': value,
        });
      } else {
        return;
      }
      tx.audit(
        action: 'SERVICE_TAX_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: setting == null
            ? 'No provincial sales tax on services'
            : 'Services taxed by ${setting.labelFor(digital: false)}, '
                  '${setting.labelFor(digital: true)}',
        before: {'service_tax': held?.read<String>('setting_value')},
        after: {'service_tax': value},
      );
    });
  }
}

/// The sale path, refusing a registered shop's bill over Rs 100,000 to a
/// walk-in who has not been named (M59).
///
/// Beneath every screen: the counter asks for the name before the money is
/// taken, but a bill restored after a kill, a quotation billed at the
/// counter or a test that calls the use case directly goes past the counter
/// and must not go past the rule. Checked on the posting itself — the total
/// the calculator worked out and the name the bill will keep — inside the
/// sale's own transaction, so a refused bill leaves nothing behind, not
/// even its number. A shop not registered for sales tax is only warned, at
/// the counter.
final class _BuyerNameSales implements SaleWriter {
  _BuyerNameSales(this._inner);

  final SaleWriter _inner;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(actor, (w) => body(_BuyerNameContext(w)));
}

final class _BuyerNameContext implements SaleWriteContext {
  _BuyerNameContext(this._inner);

  final SaleWriteContext _inner;

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
    if (buyerNameNeeded(
          total: doc.total,
          partyId: doc.partyId,
          buyerName: doc.partyNameSnapshot,
        ) &&
        (await _inner.taxContextFor(null)).isSellerRegistered) {
      throw BuyerNameRequired(doc.total);
    }
    return _inner.apply(posting);
  }
}
