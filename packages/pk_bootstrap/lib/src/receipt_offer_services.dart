part of 'app_services.dart';

/// A receipt ready to offer when money has moved (M70): who it is for, the
/// number WhatsApp reaches them on, the words in their language, and how
/// they are offered it.
final class MoneyReceiptReady {
  const MoneyReceiptReady({
    required this.event,
    required this.partyId,
    required this.name,
    required this.whatsapp,
    required this.message,
    required this.language,
    required this.offer,
    this.phone,
    this.ownChoice,
  });

  final MoneyMoved event;
  final String partyId;
  final String name;

  /// As the khata keeps it, for the screen.
  final String? phone;

  /// As WhatsApp addresses it: 923004471203.
  final String whatsapp;

  final String message;
  final ReminderLanguage language;

  /// Asked, or opened by itself. Never [ReceiptOffer.never]: a party never
  /// offered one has no receipt ready.
  final ReceiptOffer offer;

  /// Their own choice; null when they are offered as the shop does.
  final ReceiptOffer? ownChoice;
}

/// The customer's receipt, offered the moment money moves (M70).
///
/// An extension, as the bill's design is (M51), so the offer lives in one
/// file beside the rest of the bootstrap.
///
/// ## Where it is kept
///
/// What a customer the shop never set is offered, and each party's own
/// choice, are rows of the firm's `settings` ([receiptOfferDefaultKey],
/// [receiptOfferPartyKey]) written through the one write path and audited,
/// so they travel with the books to a second counter and a new phone. The
/// language is the party's reminder language (M39), read where M39 keeps
/// it. No schema change.
///
/// ## What leaves the phone
///
/// Nothing, from here. This writes the words; the screen hands them to
/// WhatsApp on the customer's own chat, and the shopkeeper presses Send.
/// When it has been handed over, [recordReceiptSent] writes it on the
/// paper's history with M54's share codes: a bill's or a return's on the
/// document, a payment's on the payment.
extension ReceiptOfferServices on AppServices {
  /// What a party nobody set is offered. Asked, until the owner says.
  Future<ReceiptOffer> receiptOfferDefault() async =>
      ReceiptOffer.tryParse(await _offerSetting(receiptOfferDefaultKey)) ??
      ReceiptOffer.ask;

  /// Sets what every party nobody set is offered. The owner's call: it is
  /// a message in the shop's name to every customer.
  Future<void> setReceiptOfferDefault(ReceiptOffer offer) async {
    require(Permission.settings);
    await _runner.run(actorNow(), (tx) async {
      await _putOfferSetting(tx, receiptOfferDefaultKey, offer.name);
      tx.audit(
        action: 'RECEIPT_OFFER_DEFAULT_SET',
        entityTable: 'settings',
        entityId: tx.actor.firmId,
        summary: 'Receipts after money moves: ${offer.name}',
        after: {'offer': offer.name},
      );
    });
  }

  /// [partyId]'s own choice, or null when they are offered as the shop does.
  Future<ReceiptOffer?> receiptOfferOf(String partyId) async =>
      ReceiptOffer.tryParse(await _offerSetting(receiptOfferPartyKey(partyId)));

  /// Keeps [partyId]'s own choice; null puts them back to the shop's.
  /// Whoever keeps the khata may: "mujhe message na karein" is said at the
  /// counter, as a reminder's opt-out is (M39).
  Future<void> setReceiptOfferOf(String partyId, ReceiptOffer? offer) async {
    require(Permission.takePayments);
    await _runner.run(actorNow(), (tx) async {
      final party = await tx.selectOne(
        'SELECT name FROM parties '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [partyId, tx.actor.firmId],
      );
      if (party == null) {
        throw StateError('No party $partyId in this shop.');
      }
      await _putOfferSetting(
        tx,
        receiptOfferPartyKey(partyId),
        offer?.name ?? '',
      );
      tx.audit(
        action: 'RECEIPT_OFFER_SET',
        entityTable: 'parties',
        entityId: partyId,
        summary:
            'Receipts to ${party.read<String>('name')}: '
            '${offer?.name ?? 'as the shop does'}',
        after: {'offer': offer?.name},
      );
    });
  }

  /// The receipt for [event], or null when there is nobody to offer it to:
  /// a walk-in, a party with no number WhatsApp can reach, or one never
  /// offered one.
  ///
  /// The party is the paper's own, read from the books, and the balance is
  /// the khata as it stands now, with this movement in it — what a
  /// customer wants to know after paying is what is left.
  Future<MoneyReceiptReady?> moneyReceipt(MoneyMoved event) async {
    final firm = await queries.currentFirm();
    if (firm == null) return null;
    final partyId = await _partyOf(firm.id, event);
    if (partyId == null) return null;
    final party = await queries.partyById(firm.id, partyId);
    if (party == null) return null;
    final number = whatsappNumber(party.phone);
    if (number == null) return null;
    final own = await receiptOfferOf(partyId);
    final offer = own ?? await receiptOfferDefault();
    if (offer == ReceiptOffer.never) return null;
    final prefs = await udhaar.queries.reminderPrefs(firm.id, partyId);
    return MoneyReceiptReady(
      event: event,
      partyId: partyId,
      name: party.name,
      phone: party.phone,
      whatsapp: number,
      message: moneyReceiptMessage(
        event,
        name: party.name,
        shop: firm.name,
        // What a supplier is owed is kept apart from what they owe.
        balanceNow: event.kind == MoneyMove.paidSupplier
            ? party.payable
            : party.balance,
        language: prefs.language,
      ),
      language: prefs.language,
      offer: offer,
      ownChoice: own,
    );
  }

  /// Writes on the paper's history that its receipt left [via], with who
  /// and when, in a transaction of its own that moves no row of the books —
  /// so a paper in closed books (M42) is recorded like any other.
  Future<void> recordReceiptSent(MoneyReceiptReady ready, SharedVia via) async {
    final event = ready.event;
    final document = event.documentId;
    final table = document != null ? 'documents' : 'payments';
    final id = document ?? event.paymentId!;
    final number = document != null ? 'doc_no' : 'payment_no';
    await _runner.run(actorNow(), (tx) async {
      final row = await tx.selectOne(
        'SELECT $number AS no FROM $table '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [id, tx.actor.firmId],
      );
      if (row == null) return;
      tx.audit(
        action: via.action,
        entityTable: table,
        entityId: id,
        summary: '${row.read<String>('no')}: ${via.words}',
        after: {
          'via': via.name,
          'receipt': ready.event.kind.name,
          'language': ready.language.code,
        },
      );
    });
  }

  /// Whose paper [event] is, as the books hold it. Null for a walk-in.
  Future<String?> _partyOf(String firmId, MoneyMoved event) async {
    final document = event.documentId;
    final row = await database
        .customSelect(
          document != null
              ? 'SELECT party_id FROM documents WHERE id = ? AND firm_id = ?'
              : 'SELECT party_id FROM payments WHERE id = ? AND firm_id = ?',
          variables: [
            Variable<String>(document ?? event.paymentId!),
            Variable<String>(firmId),
          ],
        )
        .getSingleOrNull();
    return row?.readNullable<String>('party_id');
  }

  Future<String?> _offerSetting(String key) async {
    final firmId = _identity?.firmId;
    if (firmId == null) return null;
    final row = await database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(key)],
        )
        .getSingleOrNull();
    return row?.read<String>('setting_value');
  }

  /// Writes [value] under [key], adding the row the first time. Read with
  /// tombstones included, as M39's settings are: the key is unique whatever
  /// the row's state.
  static Future<void> _putOfferSetting(Tx tx, String key, String value) async {
    final held = await tx.selectOne(
      'SELECT id, deleted_at_utc FROM settings '
      'WHERE firm_id = ? AND setting_key = ?',
      [tx.actor.firmId, key],
    );
    if (held == null) {
      await tx.insert('settings', {
        'setting_key': key,
        'setting_value': value,
        'value_type': 'string',
      });
    } else if (held.readNullable<int>('deleted_at_utc') == null) {
      await tx.update('settings', held.read<String>('id'), {
        'setting_value': value,
      });
    } else {
      throw StateError('Setting $key was deleted and cannot be written.');
    }
  }
}
