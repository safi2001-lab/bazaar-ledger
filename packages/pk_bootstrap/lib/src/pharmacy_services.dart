part of 'app_services.dart';

/// The pharmacy pack (M49): the shop's standing as a chemist, a medicine's
/// substitutes, the DRAP price at the counter, batches held and let go, the
/// near-expiry list by supplier and the return that sends it back, and the
/// photograph of a prescription.
///
/// ## Who may do what
///
/// Anybody at the counter is held to the printed price and asked for a
/// prescription. Only whoever may change the shop's settings — the owner —
/// sets the shop's discount off the MRP. Holding a batch, letting it go and
/// sending stock back to a supplier move stock the shop paid for, so they
/// take the purchases permission, as a delivery does: a cashier who could
/// let a recalled batch go could sell it.
final class PharmacyServices {
  PharmacyServices._(this._app);

  final AppServices _app;

  DriftPharmacyReads get _reads => DriftPharmacyReads(_app.database);

  DriftPharmacyWriter get _writer => DriftPharmacyWriter(_app._runner);

  /// The shop's standing: a pharmacy or not, and its discount off the MRP.
  Future<PharmacyRules> rules() async {
    final id = _app._identity;
    if (id == null) return PharmacyRules.none;
    return _reads.rulesFor(id.firmId);
  }

  /// Whether whoever is signed in may set the shop's discount off the MRP.
  bool get canSetRules => _app.can(Permission.settings);

  /// Whether whoever is signed in may hold a batch or send stock back.
  bool get canMoveBatches => _app.can(Permission.purchases);

  /// Sets "10% off on all medicines" — [bp] basis points off the printed
  /// price of every item that has one, from the next line rung.
  Future<void> setOffMrp(int bp) async {
    _app.require(Permission.settings);
    await _writer.setOffMrp(_app.actorNow(), bp);
  }

  /// The items with [itemId]'s salt and strength, the ones on the shelf
  /// first.
  Future<List<ItemSummary>> substitutes(String itemId) async {
    final id = _app._identity;
    if (id == null) return const [];
    return _reads.substitutes(id.firmId, itemId);
  }

  /// Each of [baseQtyByItem]'s items as the pharmacy rules read it at this
  /// counter: its schedule, and the most that much of it may be sold for,
  /// batch by batch. The same read the sale path refuses with.
  Future<Map<String, MedicineOnBill>> atCounter(
    Map<String, Qty> baseQtyByItem,
  ) async {
    if (baseQtyByItem.isEmpty || _app._identity == null) return const {};
    return _reads.medicinesFor(
      _app.actorNow(),
      baseQtyByItem,
      locationCode: await _app.counterLocation(),
    );
  }

  /// Why batch [lotNo] of [itemId] may not be sold, when it is on hold:
  /// what a pack scanned at the counter is refused in.
  Future<String?> holdReasonOf(String itemId, String lotNo) async {
    final id = _app._identity;
    if (id == null) return null;
    return _reads.holdReasonOf(id.firmId, itemId, lotNo);
  }

  /// Every batch on the shop floor that expires within [days] (or has
  /// already), or is on hold, under the supplier it came from.
  Future<List<SupplierExpiries>> nearExpiry({int days = 30}) async {
    final id = _app._identity;
    if (id == null) return const [];
    final today = BusinessDate.now(_app.clock);
    return expiriesBySupplier(
      await _reads.expiringBatches(id.firmId, before: today.addDays(days + 1)),
    );
  }

  /// Puts batch [lotId] on hold: the counter refuses it in [reason]'s words.
  Future<void> holdBatch(String lotId, String reason) async {
    _app.require(Permission.purchases);
    await _writer.holdBatch(_app.actorNow(), lotId, reason);
  }

  /// Lets batch [lotId] be sold again.
  Future<void> releaseBatch(String lotId) async {
    _app.require(Permission.purchases);
    await _writer.releaseBatch(_app.actorNow(), lotId);
  }

  /// Sends [batches] — all of each, every one from [supplierId] — back to
  /// the supplier, in one transaction: a return against each delivery the
  /// batches came in on (M5's path), each batch's stock out of that batch.
  ///
  /// What the returns credit comes off what the shop owes on each delivery.
  /// Where a delivery is already paid, M5's rule stands — the books have no
  /// account for money a supplier owes the shop — so the rest is written as
  /// handed back in cash, and the screen says so before it is sent.
  Future<ExpiryReturnDone> returnToSupplier(
    String supplierId,
    List<ExpiringBatch> batches, {
    required String reason,
  }) async {
    _app.require(Permission.purchases);
    if (batches.isEmpty) {
      throw const ReturnRefused('Nothing was picked to go back.');
    }
    if (batches.any((b) => b.supplierId != supplierId)) {
      throw const ReturnRefused(
        'Every batch on one return has to have come from that supplier.',
      );
    }
    final actor = _app.actorNow();
    final sources = await _reads.deliveriesInto([
      for (final b in batches) b.lotId,
    ]);
    final cash = await _cashAccount(actor.firmId);
    final recorded = <RecordedPurchaseReturn>[];
    await _writer.returnsTogether(
      actor,
      {for (final b in batches) b.lotId: b.qty},
      (writer) async {
        final plan = await writer.inTransaction(
          actor,
          (ctx) => _plan(ctx, batches, sources),
        );
        for (final MapEntry(key: documentId, value: lines) in plan.entries) {
          final delivery = lines.delivery;
          final credit = Money.sum([
            for (final l in lines.drafts)
              delivery.lines
                  .firstWhere((b) => b.documentLineId == l.documentLineId)
                  .shareOf(
                    delivery.lines
                        .firstWhere((b) => b.documentLineId == l.documentLineId)
                        .baseOf(l.qty),
                  )
                  .credit,
          ]);
          final over = credit - delivery.outstanding;
          final refund = over.isPositive ? over : Money.zero;
          if (refund.isPositive && cash == null) {
            throw const ReturnRefused(
              'Part of this delivery is already paid, so that part comes back '
              'in cash, and the shop has no cash account to take it into.',
            );
          }
          recorded.add(
            await RecordPurchaseReturnUseCase(writer: writer)(
              actor,
              PurchaseReturnDraft(
                originalDocumentId: documentId,
                lines: lines.drafts,
                reason: reason,
                refundNow: refund,
                paymentAccountId: refund.isPositive ? cash : null,
              ),
            ),
          );
        }
      },
    );
    return ExpiryReturnDone(
      supplierName: batches.first.supplierName ?? '',
      returnNos: [for (final r in recorded) r.docNo],
      batches: batches,
      credited: Money.sum([for (final r in recorded) r.againstBill]),
      refunded: Money.sum([for (final r in recorded) r.refunded]),
    );
  }

  /// Which delivery line each batch goes back against, and how much, in the
  /// unit the line was billed in: each batch against the deliveries that put
  /// stock into it, oldest first, up to what each line can still take back.
  Future<
    Map<String, ({ReturnableDelivery delivery, List<ReturnLineDraft> drafts})>
  >
  _plan(
    PurchaseReturnWriteContext ctx,
    List<ExpiringBatch> batches,
    Map<String, List<({String documentId, String lineId, Qty qty})>> sources,
  ) async {
    final deliveries = <String, ReturnableDelivery>{};
    final taken = <String, Qty>{};
    final out =
        <
          String,
          ({ReturnableDelivery delivery, List<ReturnLineDraft> drafts})
        >{};
    for (final batch in batches) {
      var left = batch.qty;
      for (final source
          in sources[batch.lotId] ??
              const <({String documentId, String lineId, Qty qty})>[]) {
        if (!left.isPositive) break;
        final delivery = deliveries[source.documentId] ??= (await ctx
            .deliveryFor(source.documentId))!;
        final line = delivery.lines.firstWhere(
          (l) => l.documentLineId == source.lineId,
        );
        final room = line.returnableBase - (taken[source.lineId] ?? Qty.zero);
        final cap = room < source.qty ? room : source.qty;
        if (!cap.isPositive) continue;
        final base = cap < left ? cap : left;
        taken[source.lineId] = (taken[source.lineId] ?? Qty.zero) + base;
        left -= base;
        (out[source.documentId] ??= (
          delivery: delivery,
          drafts: [],
        )).drafts.add(
          ReturnLineDraft(
            documentLineId: source.lineId,
            qty: _inBilledUnit(line, base, batch),
            lotId: batch.lotId,
          ),
        );
      }
      if (left.isPositive) {
        throw ReturnRefused(
          '${left.display} ${batch.unitCode} of batch ${batch.lotNo} '
          '(${batch.itemName}) came in on no delivery that can take it back: '
          'opening stock, or a delivery already returned. Write it off as a '
          'stock correction instead.',
        );
      }
    }
    return out;
  }

  /// [base] of [line]'s item in the unit the line was billed in, exactly.
  static Qty _inBilledUnit(BoughtLine line, Qty base, ExpiringBatch batch) {
    if (line.qty.inThousandths == line.boughtQty.inThousandths) return base;
    if (base == line.returnableBase) return line.returnable;
    final numerator = base.inThousandths * line.qty.inThousandths;
    if (numerator % line.boughtQty.inThousandths != 0) {
      throw ReturnRefused(
        '${base.display} ${batch.unitCode} of batch ${batch.lotNo} does not '
        'come out even in the ${line.unitCode} it was bought in. Send it back '
        'from the delivery itself.',
      );
    }
    return Qty.raw(numerator ~/ line.boughtQty.inThousandths);
  }

  Future<String?> _cashAccount(String firmId) async {
    final accounts = await _app.queries.paymentAccounts(firmId);
    final cash = accounts.where((a) => a.modeLabel == 'cash').toList();
    return cash.isEmpty ? null : cash.first.id;
  }

  /// Keeps a photograph of the paper prescription with the bill
  /// [documentId] whose Schedule lines it covers. Replaces any earlier one.
  Future<void> attachPrescriptionPhoto(
    String documentId, {
    required Uint8List source,
    required String fileName,
  }) async {
    _app.require(Permission.sell);
    final shrunk = await const DartImageShrinker().shrink(
      source,
      id: documentId,
    );
    await _app.pictures._store.attach(
      _app.actorNow(),
      kind: 'other',
      ownerTable: 'prescriptions',
      ownerId: documentId,
      image: shrunk,
      fileName: fileName,
    );
  }

  /// The photograph of [documentId]'s prescription, when one was taken.
  Future<ImageAttachment?> prescriptionPhoto(String documentId) async {
    final id = _app._identity;
    if (id == null) return null;
    return _app.pictures._store.forOwner(
      id.firmId,
      'prescriptions',
      documentId,
    );
  }
}
