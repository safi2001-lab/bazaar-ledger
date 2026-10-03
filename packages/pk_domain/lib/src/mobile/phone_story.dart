/// A phone's whole story, and the used phones the shop buys over the
/// counter (M50).
///
/// "Ye phone aap ne kis se liya tha?" A customer whose phone was snatched
/// asks it; so does the policeman holding a phone with that IMEI; so does
/// the man whose phone PTA has just blocked. The shop's answer is the
/// phone's story: bought from whom, when and for how much; sold to whom, on
/// which bill; brought back, sent back; its warranty, its PTA standing, the
/// photographs of the paper. Every line of it is already in the books —
/// the stock ledger moves the phone by its IMEI — and this is that read,
/// put in order.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'imei.dart';

/// One phone, as a search for its IMEI finds it.
final class PhoneUnit {
  const PhoneUnit({
    required this.lotId,
    required this.itemId,
    required this.itemName,
    required this.imei1,
    required this.onHand,
    this.imei2,
    this.pta,
    this.ptaCheckedOn,
  });

  final String lotId;
  final String itemId;
  final String itemName;

  /// The number the phone is kept by: M11's serial, SIM slot 1.
  final String imei1;
  final String? imei2;
  final PtaStatus? pta;
  final BusinessDate? ptaCheckedOn;

  /// Whether it is in the shop now (anywhere: the floor, a godown, a van).
  final bool onHand;

  /// Both IMEIs, the second only when it has one.
  List<String> get imeis => [imei1, ?imei2];
}

/// What happened to a phone on one day.
enum PhoneEventKind {
  /// It came in on a delivery, or was bought over the counter.
  bought,

  /// It went out on a bill.
  sold,

  /// A customer brought it back.
  returned,

  /// It went back to the supplier.
  sentBack,

  /// Moved between the shop floor, a godown and a van.
  moved,

  /// On the books before the shop kept it by IMEI, or put right by hand.
  adjusted,
}

/// One line of a phone's story.
final class PhoneEvent {
  const PhoneEvent({
    required this.kind,
    required this.on,
    this.documentId,
    this.docNo,
    this.partyId,
    this.partyName,
    this.amount,
    this.warrantyUntil,
    this.cancelled = false,
  });

  final PhoneEventKind kind;
  final BusinessDate on;
  final String? documentId;

  /// The number on the paper it moved on: the bill, the delivery.
  final String? docNo;
  final String? partyId;

  /// The supplier it came from, the customer it went to: as the paper names
  /// them.
  final String? partyName;

  /// What it cost on a delivery, what it sold for on a bill. Null where the
  /// paper carries no price for it, and for a role that may not see costs.
  final Money? amount;

  /// For a sale: the day its warranty ends, as the bill stamped it.
  final BusinessDate? warrantyUntil;

  /// The paper it moved on was cancelled since.
  final bool cancelled;
}

/// A warranty claim written against a phone.
final class WarrantyClaim {
  const WarrantyClaim({
    required this.id,
    required this.on,
    required this.note,
    this.byName,
  });

  final String id;
  final BusinessDate on;
  final String note;

  /// Who wrote it down.
  final String? byName;
}

/// Who sold the shop a used phone, as the register writes them.
final class UsedPhoneSeller {
  const UsedPhoneSeller({
    required this.name,
    required this.cnic,
    this.phone,
    this.partyId,
    this.conditionNote,
  });

  final String name;

  /// Thirteen digits.
  final String cnic;
  final String? phone;

  /// The supplier the seller is kept as, found again by CNIC.
  final String? partyId;

  /// What state the phone was in, as the shop saw it.
  final String? conditionNote;
}

/// A phone's story, in the order it happened.
final class PhoneStory {
  const PhoneStory({
    required this.unit,
    required this.events,
    this.seller,
    this.boughtUsedOn,
    this.claims = const [],
    this.warrantyKind,
    this.qistPlanId,
  });

  final PhoneUnit unit;

  /// Oldest first.
  final List<PhoneEvent> events;

  /// When it was bought used over the counter: who sold it, and the
  /// delivery it came in on.
  final UsedPhoneSeller? seller;
  final String? boughtUsedOn;

  final List<WarrantyClaim> claims;

  /// Whose warranty the item carries now.
  final WarrantyKind? warrantyKind;

  /// The qist plan it was last sold on, if it was.
  final String? qistPlanId;

  /// Its last sale that still stands.
  PhoneEvent? get lastSale => events.reversed
      .where((e) => e.kind == PhoneEventKind.sold && !e.cancelled)
      .firstOrNull;

  /// The day its warranty ends, from its last sale that still stands, when
  /// that sale gave it one.
  BusinessDate? get warrantyUntil => lastSale?.warrantyUntil;

  /// Whether it is still under warranty on [today]: sold, not back in the
  /// shop, and not past the day the bill gave it.
  bool inWarrantyOn(BusinessDate today) {
    final until = warrantyUntil;
    return until != null &&
        !unit.onHand &&
        until.value.compareTo(today.value) >= 0;
  }
}

/// One used phone bought over the counter, as the register lists it for
/// the police and the market association.
final class UsedPhoneBuy {
  const UsedPhoneBuy({
    required this.documentId,
    required this.docNo,
    required this.on,
    required this.seller,
    required this.itemName,
    required this.imei1,
    required this.price,
    this.imei2,
    this.pta,
    this.lotId,
    this.cancelled = false,
  });

  final String documentId;
  final String docNo;
  final BusinessDate on;
  final UsedPhoneSeller seller;
  final String itemName;
  final String imei1;
  final String? imei2;
  final PtaStatus? pta;
  final String? lotId;

  /// What the shop paid the seller.
  final Money price;

  /// The purchase was cancelled since.
  final bool cancelled;
}

/// Why a used-phone purchase was refused, in words.
final class UsedPhoneRefused implements Exception {
  const UsedPhoneRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A used phone, as the counter takes it in from whoever walked in with it.
final class UsedPhoneBuyDraft {
  const UsedPhoneBuyDraft({
    required this.sellerName,
    required this.sellerCnic,
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitCode,
    required this.phone,
    required this.price,
    required this.paymentAccountId,
    this.sellerPhone,
    this.conditionNote,
  });

  final String sellerName;

  /// As typed: "35202-1234567-1" or thirteen digits.
  final String sellerCnic;
  final String? sellerPhone;
  final String? conditionNote;

  /// The model, as an item kept by IMEI.
  final String itemId;
  final String itemName;
  final String unitId;
  final String unitCode;

  final PhoneUnitDraft phone;

  /// Paid to the seller, in cash or however it was handed over.
  final Money price;

  /// The drawer or account it came out of.
  final String paymentAccountId;

  /// The CNIC as kept: thirteen digits.
  String get cnic => cnicDigits(sellerCnic);

  /// Refuses a draft the register cannot stand behind, in words: no seller,
  /// a CNIC not in form, a mistyped IMEI, nothing paid.
  void check() {
    if (sellerName.trim().isEmpty) {
      throw const UsedPhoneRefused(
        'Write the seller\'s name: a used phone bought from nobody in '
        'particular is the phone the register exists to account for.',
      );
    }
    if (!cnicWellFormed(sellerCnic)) {
      throw UsedPhoneRefused(
        'The seller\'s CNIC "${sellerCnic.trim()}" is not 13 digits '
        '(12345-1234567-1).',
      );
    }
    phone.check();
    if (!price.isPositive) {
      throw const UsedPhoneRefused('Write what was paid for the phone.');
    }
  }
}
