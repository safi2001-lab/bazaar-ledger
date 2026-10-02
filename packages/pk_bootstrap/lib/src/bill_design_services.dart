part of 'app_services.dart';

/// One bill, made into the paper this shop hands over (M51), with the design
/// it is to be drawn in.
final class PreparedBill {
  const PreparedBill({
    required this.receipt,
    required this.design,
    this.extras,
  });

  /// The receipt read, dressed: the sheet chosen, the khata block, the
  /// shop's footer, its logo and its payment QR.
  final ReceiptData receipt;

  final BillDesign design;

  /// What the paper was dressed from. Null only for a document the extras
  /// read could not find, which the receipt read then found anyway.
  final BillExtras? extras;

  /// Whether goods leave the shop on this paper, so a transporter's copy of
  /// it means something.
  bool get sendsGoods => extras?.sendsGoods ?? false;

  /// How the goods travel, as the bill holds it now.
  ReceiptTransport get transport => extras?.transport ?? ReceiptTransport.none;
}

/// How the shop's bills look, and the pictures on them (M51).
///
/// An extension rather than a field, so the bill's design lives in one file
/// beside the rest of the bootstrap without another constructor argument
/// for every caller of [AppServices] to thread through.
///
/// ## Where it is kept
///
/// The design is one JSON value in the firm's own `settings` row under
/// [BillDesign.settingKey]; the logo and the payment QR are attachments of
/// kind `logo` and `bank_qr`, which the schema has carried since v1 for
/// exactly this. Both travel with the books — into a backup, onto a second
/// counter over sync, onto a new phone — so a shop's bills look the same on
/// every phone it bills from. Nothing about it is a schema change.
///
/// The attachment store keeps one picture per owner, so the two pictures
/// cannot both hang off the firm's row: the logo does, and the QR hangs off
/// [_qrOwner] with the firm's id. The owner reference is loose by design —
/// the schema says so — and this is the case it is loose for.
extension BillDesignServices on AppServices {
  static const _qrOwner = 'firm_payment_qr';

  String? get _designFirm => _identity?.firmId;

  /// How this shop's bills look. The default until the owner changes it.
  Future<BillDesign> billDesign() async {
    final firmId = _designFirm;
    if (firmId == null) return const BillDesign();
    final row = await database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(BillDesign.settingKey),
          ],
        )
        .getSingleOrNull();
    return BillDesign.fromJson(row?.read<String>('setting_value'));
  }

  /// Keeps [design] as how this shop's bills look, from the next bill out.
  Future<void> saveBillDesign(BillDesign design) async {
    require(Permission.settings);
    final actor = actorNow();
    final value = design
        .copyWith(footerLines: BillDesign.tidyFooter(design.footerLines))
        .toJson();
    await _runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id FROM settings WHERE firm_id = ? AND setting_key = ? '
        'AND deleted_at_utc IS NULL',
        [actor.firmId, BillDesign.settingKey],
      );
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': BillDesign.settingKey,
          'setting_value': value,
          'value_type': 'json',
        });
      } else {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': value,
        });
      }
      tx.audit(
        action: 'BILL_DESIGN_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary:
            'Bills now ${design.theme.name}, ${design.accent.name}, '
            '${design.pageSize.name.toUpperCase()}',
      );
    });
  }

  /// The shop's logo, as it goes on a PDF, or null.
  Future<ImageAttachment?> shopLogo() async {
    final firmId = _designFirm;
    if (firmId == null) return null;
    return pictures._store.forOwner(firmId, 'firms', firmId);
  }

  /// Makes [source] the shop's logo, replacing any before it.
  ///
  /// Throws [FormatException] when the bytes are not a picture, which the
  /// screen says in words.
  Future<void> setShopLogo(Uint8List source, {required String fileName}) async {
    require(Permission.settings);
    final actor = actorNow();
    await pictures._store.attach(
      actor,
      kind: 'logo',
      ownerTable: 'firms',
      ownerId: actor.firmId,
      image: prepareShopLogo(source, id: actor.firmId),
      fileName: fileName,
    );
  }

  Future<void> clearShopLogo() async {
    require(Permission.settings);
    final actor = actorNow();
    await pictures._store.detach(
      actor,
      ownerTable: 'firms',
      ownerId: actor.firmId,
    );
  }

  /// The payment QR the shop's own bank or wallet issued it, as the owner
  /// added it, or null. Never one this app made: there is no code anywhere
  /// in it that could.
  Future<ImageAttachment?> paymentQr() async {
    final firmId = _designFirm;
    if (firmId == null) return null;
    return pictures._store.forOwner(firmId, _qrOwner, firmId);
  }

  /// Keeps a picture of the shop's own payment QR, replacing any before it.
  Future<void> setPaymentQr(
    Uint8List source, {
    required String fileName,
  }) async {
    require(Permission.settings);
    final actor = actorNow();
    await pictures._store.attach(
      actor,
      kind: 'bank_qr',
      ownerTable: _qrOwner,
      ownerId: actor.firmId,
      image: preparePaymentQr(source, id: actor.firmId),
      fileName: fileName,
    );
  }

  Future<void> clearPaymentQr() async {
    require(Permission.settings);
    final actor = actorNow();
    await pictures._store.detach(
      actor,
      ownerTable: _qrOwner,
      ownerId: actor.firmId,
    );
  }

  /// Writes how the goods on [documentId] travel.
  ///
  /// The four columns are the bill's non-fiscal fields, which the schema
  /// keeps editable on a posted bill on purpose: the bilty number is handed
  /// over at the adda after the bill is printed. Nothing that is money or
  /// tax is touched, and the change is audited with what it was and what it
  /// became. Whoever may sell may write it, as they wrote the bill.
  Future<void> setTransportDetails(
    String documentId,
    ReceiptTransport transport,
  ) async {
    require(Permission.sell);
    final actor = actorNow();
    String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    final after = {
      'transporter': clean(transport.transporter),
      'vehicle_no': clean(transport.vehicleNo),
      'bilty_no': clean(transport.biltyNo),
      'ship_to': clean(transport.shipTo),
    };
    await _runner.run(actor, (tx) async {
      final before = await tx.selectOne(
        'SELECT doc_no, transporter, vehicle_no, bilty_no, ship_to '
        'FROM documents WHERE id = ? AND firm_id = ? '
        'AND deleted_at_utc IS NULL',
        [documentId, actor.firmId],
      );
      if (before == null) {
        throw StateError('No bill $documentId in this shop.');
      }
      final was = {
        for (final key in after.keys) key: before.readNullable<String>(key),
      };
      if (after.keys.every((k) => was[k] == after[k])) return;
      await tx.update('documents', documentId, after);
      tx.audit(
        action: 'DOCUMENT_TRANSPORT_SET',
        entityTable: 'documents',
        entityId: documentId,
        summary: 'Transport details on ${before.read<String>('doc_no')}',
        before: was,
        after: after,
      );
    });
  }

  /// [documentId] as the paper this shop hands over: [copy] if one was
  /// chosen, in [design] (the saved one when null), with the payment QR as
  /// till-roll dots when [thermal] names the paper and the design asks for
  /// it.
  ///
  /// The receipt read underneath is the one every bill has always printed
  /// from; this only adds to it. Null if the document is not this shop's.
  Future<PreparedBill?> billPaper(
    String documentId, {
    ReceiptCopy? copy,
    ReceiptPaper? thermal,
    BillDesign? design,
  }) async {
    final firm = await queries.currentFirm();
    if (firm == null) return null;
    final base = await queries.receiptFor(firm.id, documentId);
    if (base == null) return null;
    final extras = await queries.billExtras(firm.id, documentId);
    final look = design ?? await billDesign();
    final logo = await shopLogo();
    final qr = await paymentQr();
    final dots = thermal != null && look.qrOnThermal && qr != null
        ? pictureDots(qr.bytes, paperDots: thermal.dots)
        : null;
    return PreparedBill(
      receipt: dressBill(
        base,
        extras: extras,
        design: look,
        copy: copy,
        logo: logo?.bytes,
        paymentQr: qr?.bytes,
        paymentQrDots: dots,
      ),
      design: look,
      extras: extras,
    );
  }
}
