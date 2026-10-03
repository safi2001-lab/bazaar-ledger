/// The mobile-shop pack's reads and writes (M50).
///
/// Its own port, as the udhaar pack's is (M38), so a phone's story and its
/// qist can grow without every other screen's reader growing with them.
library;

import '../identity/actor_context.dart';
import '../mobile/imei.dart';
import '../mobile/phone_story.dart';
import '../mobile/qist.dart';
import '../time/clock.dart';

/// What the phone search, a phone's story, the qist pages and the mobile
/// reports read.
abstract interface class MobileQueries {
  /// Phones whose IMEI 1 or IMEI 2 holds [digits] anywhere — the last five
  /// digits a customer reads off the back of the box are enough — those in
  /// the shop first, then the newest.
  Future<List<PhoneUnit>> findPhones(
    String firmId,
    String digits, {
    int limit = 30,
  });

  /// One phone, by its lot.
  Future<PhoneUnit?> phoneUnit(String firmId, String lotId);

  /// [lotId]'s whole story. Purchase costs are left out when [withCosts] is
  /// false, for a role that may not see what goods cost.
  Future<PhoneStory?> phoneStory(
    String firmId,
    String lotId, {
    bool withCosts = true,
  });

  /// Every used phone bought over the counter between [from] and [to]
  /// (inclusive; either open), newest first, cancelled ones marked.
  Future<List<UsedPhoneBuy>> usedPhonesBought(
    String firmId, {
    BusinessDate? from,
    BusinessDate? to,
  });

  /// The seller who last sold the shop a phone on [cnic] (13 digits), so a
  /// returning seller is filled in and kept as the same supplier.
  Future<UsedPhoneSeller?> sellerByCnic(String firmId, String cnic);

  /// Every qist plan, or one customer's, newest first.
  Future<List<QistPlan>> qistPlans(String firmId, {String? partyId});

  /// One plan.
  Future<QistPlan?> qistPlan(String firmId, String planId);

  /// The plan the bill [documentId] was sold on, if any.
  Future<QistPlan?> qistPlanForBill(String firmId, String documentId);
}

/// What the mobile-shop pack writes, through the one write path.
abstract interface class MobileStore {
  /// Writes down what PTA said of [lotId], today.
  Future<void> setPta(ActorContext actor, String lotId, PtaStatus status);

  /// Gives [lotId] its second IMEI, checked, when it came in without one.
  Future<void> setImei2(ActorContext actor, String lotId, String imei2);

  /// Writes a warranty claim against [lotId].
  Future<String> recordWarrantyClaim(
    ActorContext actor,
    String lotId,
    String note,
  );

  /// Closes [planId] early: from today, whatever is left on its bill is due
  /// at once.
  Future<void> closeQistEarly(
    ActorContext actor,
    String planId, {
    String? note,
  });
}

/// Why a mobile-shop write was refused, in words.
final class MobileRefused implements Exception {
  const MobileRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
