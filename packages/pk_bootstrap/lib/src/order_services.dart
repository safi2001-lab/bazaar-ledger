part of 'app_services.dart';

/// Purchase orders, sale orders, the shortage list and what to order
/// (M41).
///
/// A purchase order takes the purchases permission, as receiving the goods
/// does: whoever may enter the mill's delivery may ask the mill for it. A
/// sale order takes the sell permission, as the bill made from it does,
/// and its advance takes the payments permission, as any receipt does. The
/// shortage list is open to whoever sells or buys: the cashier is the one
/// standing there when a customer asks for something the shelf does not
/// have.
final class OrderServices {
  OrderServices._(this._app);

  final AppServices _app;

  DriftOrderReads get _reads => DriftOrderReads(_app.database);
  DriftOrderWriter get _writer =>
      DriftOrderWriter(runner: _app._runner, ids: _app.ids);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('No shop is set up on this phone yet.');
    return id.firmId;
  }

  void _mayHandle(OrderKind kind) => _app.require(
    kind == OrderKind.purchase ? Permission.purchases : Permission.sell,
  );

  /// Whether whoever is signed in may see and write [kind]'s orders.
  bool canHandle(OrderKind kind) => _app.can(
    kind == OrderKind.purchase ? Permission.purchases : Permission.sell,
  );

  /// Whether whoever is signed in may use the shortage list.
  bool get canNoteShortage =>
      _app.can(Permission.sell) || _app.can(Permission.purchases);

  void _mayNoteShortage() {
    if (!canNoteShortage) _app.require(Permission.sell);
  }

  // -------------------------------------------------------------------------
  // Orders
  // -------------------------------------------------------------------------

  /// [kind]'s orders, newest first; with [standingOnly], only those with
  /// something still to come; with [partyId], only that party's.
  Future<List<OrderRow>> list(
    OrderKind kind, {
    bool standingOnly = false,
    String? partyId,
  }) async {
    _mayHandle(kind);
    return _reads.orders(
      _firmId,
      kind,
      standingOnly: standingOnly,
      partyId: partyId,
    );
  }

  /// One order, opened, or null when it is not one of this shop's.
  Future<OrderView?> order(String orderId) async {
    final view = await _reads.order(_firmId, orderId);
    if (view != null) _mayHandle(view.row.kind);
    return view;
  }

  /// Places [draft]. Returns its id and number.
  Future<({String id, String docNo})> place(OrderDraft draft) async {
    _mayHandle(draft.kind);
    return _writer.save(_app.actorNow(), draft);
  }

  /// Places every one of [drafts] in one commit: one purchase order per
  /// supplier from the reorder screen, all or none.
  Future<List<({String id, String docNo})>> placeAll(
    List<OrderDraft> drafts,
  ) async {
    for (final kind in {for (final d in drafts) d.kind}) {
      _mayHandle(kind);
    }
    return _writer.saveAll(_app.actorNow(), drafts);
  }

  /// Cancels [orderId], saying why. What already came of it stands.
  Future<void> cancel(String orderId, {required String reason}) async {
    final view = await order(orderId);
    if (view == null) {
      throw const OrderRefused('That is not an order of this shop.');
    }
    await _writer.cancel(_app.actorNow(), orderId: orderId, reason: reason);
  }

  /// Takes [amount] from the customer against sale order [orderId], as a
  /// receipt on their khata held whole for the bill the order becomes.
  ///
  /// The receipt names the order by its number, which is how the bill made
  /// from the order finds it, and how the receipt reads on the khata.
  Future<RecordedReceipt> takeAdvance(
    String orderId, {
    required Money amount,
    required String paymentAccountId,
    required String mode,
  }) async {
    final view = await order(orderId);
    if (view == null || view.row.kind != OrderKind.sale) {
      throw const OrderRefused('That is not a sale order of this shop.');
    }
    if (!view.row.status.isStanding) {
      throw OrderRefused(
        '${view.row.docNo} is not open, so nothing is taken against it.',
      );
    }
    if (!amount.isPositive) {
      throw const OrderRefused('How much was paid down?');
    }
    return _app.recordReceipt(
      _app.actorNow(),
      ReceiptDraft(
        partyId: view.row.partyId,
        amount: amount,
        mode: mode,
        paymentAccountId: paymentAccountId,
        reference: view.row.docNo,
        notes: 'Advance on ${view.row.docNo}',
        holdAsAdvance: true,
      ),
    );
  }

  /// The words purchase order [orderId] travels in on WhatsApp: what is
  /// still to come of it, at the rates it was placed at.
  Future<String?> purchaseOrderText(String orderId) async {
    final view = await order(orderId);
    final firm = await _app.queries.currentFirm();
    if (view == null || firm == null) return null;
    return purchaseOrderMessage(
      shopName: firm.name,
      docNo: view.row.docNo,
      supplierName: view.row.partyName,
      due: view.row.dueDate,
      notes: view.notes,
      lines: [
        for (final l in view.lines)
          if (!l.isDone)
            switch (l.pendingInOrderUnit) {
              final q? => (
                name: l.itemName,
                qty: q,
                unit: l.unitCode,
                rate: l.rate,
              ),
              null => (
                name: l.itemName,
                qty: l.pendingBase,
                unit: l.baseUnitCode,
                rate: l.baseRate,
              ),
            },
      ],
    );
  }

  /// The number WhatsApp can reach [orderId]'s party on, if there is one.
  Future<String?> whatsappFor(String orderId) async {
    final recipient = await _app.queries.recipientOf(_firmId, orderId);
    return whatsappNumber(recipient?.phone);
  }

  // -------------------------------------------------------------------------
  // The shortage list
  // -------------------------------------------------------------------------

  /// What customers asked for that is still to get, oldest first.
  Future<List<ShortageEntry>> shortage() async {
    _mayNoteShortage();
    return _reads.shortage(_firmId);
  }

  /// Puts [draft] on the shortage list. Returns the line's id.
  Future<String> noteShortage(ShortageDraft draft) async {
    _mayNoteShortage();
    return _writer.addShortage(_app.actorNow(), draft);
  }

  /// Takes [entryIds] off the shortage list.
  Future<void> clearShortage(List<String> entryIds) async {
    _mayNoteShortage();
    await _writer.clearShortage(_app.actorNow(), entryIds);
  }

  /// The shortage list in words, to send on.
  Future<String> shortageText() async {
    final firm = await _app.queries.currentFirm();
    return shortageMessage(
      shopName: firm?.name ?? '',
      entries: await shortage(),
    );
  }

  // -------------------------------------------------------------------------
  // What to order
  // -------------------------------------------------------------------------

  /// What to order now, grouped by the supplier each item last came from.
  Future<List<ReorderGroup>> reorder() async {
    _app.require(Permission.purchases);
    return groupBySupplier(
      await _reads.reorder(_firmId, BusinessDate.now(_app.clock)),
    );
  }
}
