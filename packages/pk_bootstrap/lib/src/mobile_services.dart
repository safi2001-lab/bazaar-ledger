part of 'app_services.dart';

/// The mobile-shop pack (M50): a phone found by any part of either IMEI and
/// its whole story; what PTA said of it; its warranty and the claims made
/// on it; a used phone bought over the counter with its seller's CNIC; and
/// phones sold on qist.
///
/// ## Who may do what
///
/// Anybody signed in may look a phone up: the counter boy is the one the
/// customer hands the box to. Writing down what PTA said and a warranty
/// claim take the selling permission, as handling a phone at the counter
/// does. Giving a phone its second IMEI changes what the stock is known by,
/// and buying a used phone puts goods on the shelf and takes cash out of the
/// drawer, so both take the purchases permission, as a delivery does.
/// Closing a qist plan early changes when money is due, so it takes the
/// permission that takes payments. What a phone cost is shown only to a role
/// that may see costs.
///
/// Nothing here leaves the phone. The PTA check is a pre-typed SMS the
/// shopkeeper sends from their own SIM ([PtaStatus], [ptaCheckSms]); the
/// seller's CNIC photograph stays where it was taken (M60).
final class MobileServices {
  MobileServices._(this._app);

  final AppServices _app;

  /// The pack's reads, for screens and the reports hub.
  DriftMobileReads get queries => DriftMobileReads(_app.database);

  DriftMobileWriter get _writer => DriftMobileWriter(_app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  /// Whether the shop says it is a mobile shop, in its details.
  Future<bool> isMobileShop() async {
    if (_app._identity == null) return false;
    return (await _app.queries.currentFirm())?.isMobileShop ?? false;
  }

  /// Phones whose IMEI 1 or 2 holds [digits] anywhere, those in the shop
  /// first.
  Future<List<PhoneUnit>> findPhones(String digits) async {
    if (_app._identity == null) return const [];
    return queries.findPhones(_firmId, digits);
  }

  /// One phone's story; what it cost only for a role that may see costs.
  Future<PhoneStory?> story(String lotId) async {
    if (_app._identity == null) return null;
    return queries.phoneStory(
      _firmId,
      lotId,
      withCosts: _app.can(Permission.seeCosts),
    );
  }

  /// One phone as the counter needs it: to warn before selling one PTA may
  /// block.
  Future<PhoneUnit?> phone(String lotId) async {
    if (_app._identity == null) return null;
    return queries.phoneUnit(_firmId, lotId);
  }

  bool get canHandlePhones => _app.can(Permission.sell);
  bool get canBuyPhones => _app.can(Permission.purchases);
  bool get canCloseQist => _app.can(Permission.takePayments);

  /// Writes down what PTA said of [lotId], today.
  Future<void> setPta(String lotId, PtaStatus status) async {
    _app.require(Permission.sell);
    await _writer.setPta(_app.actorNow(), lotId, status);
  }

  /// Gives [lotId] its second IMEI.
  Future<void> setImei2(String lotId, String imei2) async {
    _app.require(Permission.purchases);
    await _writer.setImei2(_app.actorNow(), lotId, imei2);
  }

  /// Writes a warranty claim against [lotId].
  Future<String> recordWarrantyClaim(String lotId, String note) async {
    _app.require(Permission.sell);
    return _writer.recordWarrantyClaim(_app.actorNow(), lotId, note);
  }

  /// The seller who last sold the shop a phone on [cnic], to fill in.
  Future<UsedPhoneSeller?> sellerByCnic(String cnic) async {
    if (_app._identity == null || !cnicWellFormed(cnic)) return null;
    return queries.sellerByCnic(_firmId, cnic);
  }

  /// Buys a used phone over the counter: one delivery (the phone onto the
  /// shelf by its IMEI at what was paid, the money out of [draft]'s
  /// account), the seller kept as a supplier found again by CNIC, and the
  /// register row, all in one transaction.
  Future<({String documentId, String docNo, String partyId, String lotId})>
  buyUsedPhone(UsedPhoneBuyDraft draft) async {
    _app.require(Permission.purchases);
    final actor = _app.actorNow();
    return _writer.buyUsedPhone(
      actor,
      draft,
      purchase: (writer, sellerPartyId) =>
          RecordPurchaseUseCase(writer: writer)(
            actor,
            PurchaseDraft(
              partyId: sellerPartyId,
              paid: draft.price,
              paymentAccountId: draft.paymentAccountId,
              notes: 'Used phone from ${draft.sellerName.trim()}',
              lines: [
                PurchaseLineDraft(
                  itemId: draft.itemId,
                  itemName: draft.itemName,
                  qty: Qty.one,
                  baseQty: Qty.one,
                  unitId: draft.unitId,
                  unitCode: draft.unitCode,
                  rate: Rate.perUnit(draft.price),
                  phones: [draft.phone],
                ),
              ],
            ),
          ),
    );
  }

  /// Every used phone bought over the counter between [from] and [to].
  Future<List<UsedPhoneBuy>> usedPhonesBought({
    BusinessDate? from,
    BusinessDate? to,
  }) async {
    if (_app._identity == null) return const [];
    return queries.usedPhonesBought(_firmId, from: from, to: to);
  }

  /// Every qist plan, or one customer's, newest first.
  Future<List<QistPlan>> plans({String? partyId}) async {
    if (_app._identity == null) return const [];
    return queries.qistPlans(_firmId, partyId: partyId);
  }

  Future<QistPlan?> plan(String planId) async {
    if (_app._identity == null) return null;
    return queries.qistPlan(_firmId, planId);
  }

  Future<QistPlan?> planForBill(String documentId) async {
    if (_app._identity == null) return null;
    return queries.qistPlanForBill(_firmId, documentId);
  }

  /// Closes [planId] early: whatever is left on its bill is due today.
  Future<void> closeQistEarly(String planId, {String? note}) async {
    _app.require(Permission.takePayments);
    await _writer.closeQistEarly(_app.actorNow(), planId, note: note);
  }

  /// Today, as the shop's books count it.
  BusinessDate get today => BusinessDate.now(_app.clock);
}
