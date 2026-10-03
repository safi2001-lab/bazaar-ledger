/// The pharmacy pack (M49): what a chemist's counter is held to, and the
/// batches that are going out of date.
///
/// ## Two rules, beneath every screen
///
///  * **The DRAP price.** A medicine's maximum retail price is fixed, and
///    selling above it is an offence; below it is the chemist's own
///    business, and "10% off on all medicines" is how most of them sell. So
///    a shop that calls itself a pharmacy is refused a bill that charges
///    more for a medicine than its printed price allows, worked out batch by
///    batch as first-expiry-first-out will take the strips: two batches of
///    one medicine on one shelf can carry two prices, and the older, cheaper
///    one goes first. The check itself is `pricing/mrp.dart`, shared with
///    the Third Schedule's printed price.
///  * **The Schedule register.** A Schedule B or D drug is sold only on a
///    registered practitioner's prescription, so a bill carrying one is
///    refused until it says who it is for and who prescribed it. Kept per
///    item, not per shop: an item flagged Schedule asks wherever it is sold.
///
/// Both are read inside the sale's own transaction, through [PharmacyReader],
/// so the figures checked are the figures the sale moves.
///
/// ## Out of date, back to the supplier
///
/// Every batch knows the delivery it came in on, and so the supplier it came
/// from. A batch expiring within the month is listed under its supplier, and
/// what is picked goes back to them as a return against that delivery (M5's
/// path, batch by batch), with a note to hand the distributor's man.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../pricing/mrp.dart';
import '../sales/sale_posting.dart';
import '../time/clock.dart';
import 'medicine.dart';

/// The settings key a pharmacy's standing discount off the printed price is
/// kept under, in basis points: 1000 is "10% off on all medicines".
const offMrpSettingKey = 'pharmacy.off_mrp_bp';

/// How a shop sells medicines.
final class PharmacyRules {
  const PharmacyRules({this.isPharmacy = false, this.offMrpBp = 0});

  /// A shop that is not a pharmacy, and has no discount off the MRP.
  static const none = PharmacyRules();

  /// The shop said so in its details.
  final bool isPharmacy;

  /// The shop's standing discount off the printed price, in basis points,
  /// on every item that has one. Zero is none.
  final int offMrpBp;

  /// Above the printed price: refused for a pharmacy, asked otherwise.
  MrpRule get mrpRule => mrpRuleFor(isPharmacy: isPharmacy);
}

/// One item on a bill, as the pharmacy rules read it.
final class MedicineOnBill {
  const MedicineOnBill({
    required this.itemId,
    required this.itemName,
    this.schedule,
    this.ceiling,
    this.refused,
  });

  final String itemId;
  final String itemName;

  /// Why the shelf cannot give this much of it, when first-expiry-first-out
  /// would have to reach a batch on hold or out of date: the words the sale
  /// path will refuse it in, so the counter can say them first.
  final String? refused;

  /// Its schedule, when it is a controlled drug.
  final ScheduleClass? schedule;

  /// The most the quantity asked about may be sold for under the printed
  /// prices of the batches it will come out of; null when none of it has a
  /// printed price.
  final Money? ceiling;
}

/// Reads what the pharmacy rules need, inside the sale's own transaction.
abstract interface class PharmacyReader {
  /// The shop's own standing: a pharmacy or not, and its discount off the
  /// printed price.
  Future<PharmacyRules> rulesFor(String firmId);

  /// Each item of [baseQtyByItem] with its schedule, and the most that much
  /// of it may be sold for at [locationCode]: batch by batch as
  /// first-expiry-first-out will take it, each at its own printed price or
  /// the item's where the batch has none.
  Future<Map<String, MedicineOnBill>> medicinesFor(
    ActorContext actor,
    Map<String, Qty> baseQtyByItem, {
    required String locationCode,
  });
}

/// What a bill charges for each item, every line of it together, after
/// discounts and with tax: what the customer pays for it.
Map<String, ({String name, Qty qty, Money charged})> chargedByItem(
  Iterable<DocumentLinePosting> lines,
) {
  final out = <String, ({String name, Qty qty, Money charged})>{};
  for (final line in lines) {
    final id = line.itemId;
    if (id == null) continue;
    final was = out[id];
    out[id] = (
      name: was?.name ?? line.itemNameSnapshot,
      qty: (was?.qty ?? Qty.zero) + line.baseQty,
      charged: (was?.charged ?? Money.zero) + line.lineTotal,
    );
  }
  return out;
}

/// Every item [charged] above what [medicines] allows.
List<MrpBreach> mrpBreaches(
  Map<String, ({String name, Qty qty, Money charged})> charged,
  Map<String, MedicineOnBill> medicines,
) => [
  for (final MapEntry(key: id, value: c) in charged.entries)
    ?aboveMrp(
      itemId: id,
      itemName: c.name,
      qty: c.qty,
      charged: c.charged,
      ceiling: medicines[id]?.ceiling,
    ),
];

/// Refuses a sale the pharmacy rules forbid: a Schedule medicine without a
/// complete prescription, wherever it is sold, and — in a pharmacy — a
/// medicine above its printed price.
///
/// Called inside the sale's transaction with the lines as they will be
/// written, so a bill restored after a kill, a quotation put on the counter
/// or an import is held to exactly what the counter is.
Future<void> refuseUnlawfulMedicineSale(
  PharmacyReader reader,
  ActorContext actor, {
  required List<DocumentLinePosting> lines,
  required Prescription? prescription,
  required String locationCode,
}) async {
  final charged = chargedByItem(lines);
  if (charged.isEmpty) return;
  final medicines = await reader.medicinesFor(actor, {
    for (final e in charged.entries) e.key: e.value.qty,
  }, locationCode: locationCode);

  final scheduled = [
    for (final m in medicines.values)
      if (m.schedule != null) m.itemName,
  ];
  if (scheduled.isNotEmpty) {
    final missing =
        prescription?.gaps ??
        const ['patient', 'prescriber', "prescriber's registration number"];
    if (missing.isNotEmpty) {
      throw PrescriptionRefused(medicines: scheduled, missing: missing);
    }
  }

  final rules = await reader.rulesFor(actor.firmId);
  if (rules.mrpRule != MrpRule.block) return;
  final breaches = mrpBreaches(charged, medicines);
  if (breaches.isNotEmpty) throw MrpRefused(breaches);
}

/// A batch on the shelf, as the near-expiry list reads it.
final class ExpiringBatch {
  const ExpiringBatch({
    required this.lotId,
    required this.itemId,
    required this.itemName,
    required this.lotNo,
    required this.qty,
    required this.unitCode,
    required this.cost,
    this.expiry,
    this.mrp,
    this.supplierId,
    this.supplierName,
    this.holdReason,
  });

  final String lotId;
  final String itemId;
  final String itemName;
  final String lotNo;

  /// What is left of it, in the item's base unit.
  final Qty qty;
  final String unitCode;

  /// Per base unit, as it came in.
  final Rate cost;
  final BusinessDate? expiry;

  /// Its printed retail price per base unit, when the delivery said.
  final Money? mrp;

  /// Who it came from: the party on the delivery that brought it in. Null
  /// for a batch that came in no delivery (opening stock, or a batch from
  /// before the shop kept them).
  final String? supplierId;
  final String? supplierName;

  /// Why it may not be sold, while it may not.
  final String? holdReason;

  bool get isHeld => holdReason != null;

  bool isExpiredOn(BusinessDate today) =>
      expiry != null && expiry!.value.compareTo(today.value) < 0;

  /// What it cost the shop.
  Money get value => cost.amountFor(qty);
}

/// One supplier's batches on the near-expiry list.
final class SupplierExpiries {
  const SupplierExpiries({
    required this.batches,
    this.supplierId,
    this.supplierName,
  });

  /// Null for the batches that came from nobody the books know.
  final String? supplierId;
  final String? supplierName;
  final List<ExpiringBatch> batches;

  Money get value => Money.sum([for (final b in batches) b.value]);
}

/// [batches] under the supplier each came from, suppliers by name and the
/// batches nobody supplied last; each supplier's batches soonest first.
List<SupplierExpiries> expiriesBySupplier(Iterable<ExpiringBatch> batches) {
  final groups = <String?, List<ExpiringBatch>>{};
  for (final b in batches) {
    (groups[b.supplierId] ??= []).add(b);
  }
  final out = [
    for (final MapEntry(key: id, value: list) in groups.entries)
      SupplierExpiries(
        supplierId: id,
        supplierName: list.first.supplierName,
        batches: list
          ..sort((a, b) {
            final ea = a.expiry?.value ?? '9999-12-31';
            final eb = b.expiry?.value ?? '9999-12-31';
            final byDate = ea.compareTo(eb);
            return byDate != 0 ? byDate : a.itemName.compareTo(b.itemName);
          }),
      ),
  ];
  out.sort((a, b) {
    if (a.supplierId == null) return b.supplierId == null ? 0 : 1;
    if (b.supplierId == null) return -1;
    return (a.supplierName ?? '').toLowerCase().compareTo(
      (b.supplierName ?? '').toLowerCase(),
    );
  });
  return out;
}

/// What a return of out-of-date stock to one supplier sent back and how it
/// was settled: one return per delivery the batches came in on.
final class ExpiryReturnDone {
  const ExpiryReturnDone({
    required this.supplierName,
    required this.returnNos,
    required this.batches,
    required this.credited,
    required this.refunded,
  });

  final String supplierName;

  /// The returns written, one per delivery.
  final List<String> returnNos;

  /// What went back, batch by batch.
  final List<ExpiringBatch> batches;

  /// What came off what the shop owes the supplier.
  final Money credited;

  /// What the supplier handed back in cash, for goods already paid for.
  final Money refunded;

  Money get total => credited + refunded;
}
