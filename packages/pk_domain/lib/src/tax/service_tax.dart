/// Provincial sales tax on services (M59).
///
/// Since the Eighteenth Amendment the tax on a service is the province's,
/// not FBR's: a salon, a mobile repair shop, a tailor or a restaurant in
/// Lahore pays the Punjab Revenue Authority, the same shop in Karachi pays the
/// Sindh Revenue Board. So a line the shop marks as a service carries the
/// province's tax and never the federal 18%, whatever the shop's federal
/// registration says.
///
/// ## The rate turns on how the customer pays
///
/// The provinces charge less when the bill is paid by card, wallet or QR,
/// to bring restaurants' takings into the banks:
///
///  * Punjab (PRA): 16%, and 8% paid by card, wallet or QR from 1 July 2026
///    (it was 5%) — for restaurants and several other services;
///  * Sindh (SRB): 15%, and 8% for restaurants paid by card or QR;
///  * Khyber Pakhtunkhwa (KPRA) and Balochistan (BRA): not checked. The owner
///    types the rates their notice gives; nothing is assumed.
///
/// The reduced rate is not every service's in either province, so the
/// owner may set it equal to the standard one and the bill then never
/// changes with the tender.
///
/// Which tenders count as "card, wallet or QR": a card, JazzCash, Easypaisa
/// and Raast. Cash, a cheque, a bank transfer and udhaar pay the standard
/// rate — a transfer is not named in either notice as this pack read them,
/// and the shopkeeper who charges the higher rate when unsure is the one
/// who is never asked for the difference.
///
/// ## A bill paid two ways: pro-rata by tender share
///
/// Part cash and part card is a bill paid two ways, and the two parts are
/// taxed at their two rates. A tender's share is the part of the bill its
/// money pays for **at its own rate**: a card payment of `c` against a bill
/// that would come to `T₈` if all of it went on the card pays the fraction
/// `f = c / T₈` of every line, at 8%, and the cash pays the rest, `1 − f` of
/// every line, at 16%. So
///
///     total = c + (1 − f) × T₁₆
///
/// and the card's own slice of the bill comes to exactly what was put on the
/// card — which is what makes the definition hold together. A share worked
/// out on the bill at the cash rate instead would leave a card that paid
/// "the whole bill" short of it.
///
/// Each service line's value is split by that share to the paisa (half up,
/// in [BigInt]) and the two parts are taxed separately, so a line can carry
/// two provincial tax rows — `PRA_STD` at 16% and `PRA_CARD` at 8% — whose
/// bases add up to the line's value exactly, and the bill's tax is the sum
/// of its rows exactly. Goods on the same bill are not touched: they carry
/// whatever the federal pack charges them.
library;

import 'package:pk_money/pk_money.dart';

import 'tax_charge.dart';
import 'third_schedule.dart' show proRataShare, taxInsidePrice;

/// The settings row that holds the shop's service-tax authority and rates.
const serviceTaxSettingKey = 'tax.service';

/// The tenders the provinces tax at the reduced rate: card, wallet, QR.
const digitalTenderModes = {'card', 'jazzcash', 'easypaisa', 'raast'};

/// Who collects the sales tax on a shop's services.
enum ServiceTaxAuthority {
  /// Punjab Revenue Authority.
  pra('pra', 'PRA', 'punjab'),

  /// Sindh Revenue Board.
  srb('srb', 'SRB', 'sindh'),

  /// Khyber Pakhtunkhwa Revenue Authority.
  kpra('kpra', 'KPRA', 'kpk'),

  /// Balochistan Revenue Authority.
  bra('bra', 'BRA', 'balochistan');

  const ServiceTaxAuthority(this.code, this.label, this.province);

  /// What is stored.
  final String code;

  /// What is printed: "PRA 8% (card)".
  final String label;

  /// The `firms.province` it collects in.
  final String province;

  /// The rates as this pack found them published, or null where they were
  /// not checked and the owner has to type them.
  ({int standardBp, int digitalBp})? get published => switch (this) {
    ServiceTaxAuthority.pra => (standardBp: 1600, digitalBp: 800),
    ServiceTaxAuthority.srb => (standardBp: 1500, digitalBp: 800),
    ServiceTaxAuthority.kpra || ServiceTaxAuthority.bra => null,
  };

  static ServiceTaxAuthority? fromCode(String? code) {
    for (final a in values) {
      if (a.code == code) return a;
    }
    return null;
  }
}

/// The shop's provincial service tax: who collects it and at what rates.
final class ServiceTaxSetting {
  const ServiceTaxSetting({
    required this.authority,
    required this.standardBp,
    required this.digitalBp,
  });

  /// The rates as published, for PRA and SRB. Null for KPRA and BRA, whose
  /// rates the owner types.
  static ServiceTaxSetting? publishedFor(ServiceTaxAuthority authority) {
    final rates = authority.published;
    if (rates == null) return null;
    return ServiceTaxSetting(
      authority: authority,
      standardBp: rates.standardBp,
      digitalBp: rates.digitalBp,
    );
  }

  final ServiceTaxAuthority authority;

  /// Paid in cash, by cheque, by bank transfer, or left on udhaar.
  final int standardBp;

  /// Paid by card, wallet or QR.
  final int digitalBp;

  /// Whether how the bill is paid changes its tax at all.
  bool get hasReducedRate => digitalBp != standardBp;

  bool isDigital(String mode) => digitalTenderModes.contains(mode);

  /// The rate a bill paid wholly by [mode] is taxed at; null is cash.
  int rateFor(String? mode) =>
      mode != null && isDigital(mode) ? digitalBp : standardBp;

  /// The `document_line_taxes.tax_code` of each part: `PRA_STD`, `PRA_CARD`.
  String codeFor({required bool digital}) =>
      '${authority.label}_${digital ? 'CARD' : 'STD'}';

  /// What a rate looks like on a bill: "PRA 16%", "PRA 8% (card)".
  String labelFor({required bool digital}) => serviceTaxLabel(
    codeFor(digital: digital),
    digital ? digitalBp : standardBp,
  );

  /// The settings row's value: `pra:1600:800`.
  String encode() => '${authority.code}:$standardBp:$digitalBp';

  /// What [raw] says, or null for nothing, "none" or anything unreadable —
  /// a shop whose setting cannot be read charges no provincial tax rather
  /// than a guessed one.
  static ServiceTaxSetting? decode(String? raw) {
    final parts = (raw ?? '').trim().split(':');
    if (parts.length != 3) return null;
    final authority = ServiceTaxAuthority.fromCode(parts[0]);
    final standard = int.tryParse(parts[1]);
    final digital = int.tryParse(parts[2]);
    if (authority == null || standard == null || digital == null) return null;
    if (!validRateBp(standard) || !validRateBp(digital)) return null;
    return ServiceTaxSetting(
      authority: authority,
      standardBp: standard,
      digitalBp: digital,
    );
  }

  /// A rate a province could charge: nothing up to fifty per cent. Anything
  /// above is a typing slip (1600 typed for 16 in a field that wanted 16).
  static bool validRateBp(int bp) => bp >= 0 && bp <= 5000;

  @override
  bool operator ==(Object other) =>
      other is ServiceTaxSetting &&
      other.authority == authority &&
      other.standardBp == standardBp &&
      other.digitalBp == digitalBp;

  @override
  int get hashCode => Object.hash(authority, standardBp, digitalBp);
}

/// "PRA 16%" or "PRA 8% (card)", from a stored tax code (`PRA_STD`,
/// `PRA_CARD`) and its rate. The "(card)" stands for card, wallet and QR
/// alike, as the provinces' own notices say "card payments".
String serviceTaxLabel(String code, int rateBp) {
  final cut = code.lastIndexOf('_');
  final who = cut < 0 ? code : code.substring(0, cut);
  final digital = code.endsWith('_CARD');
  return '$who ${percentOfBp(rateBp)}${digital ? ' (card)' : ''}';
}

/// `1600` is "16%", `850` is "8.5%", `1275` is "12.75%".
String percentOfBp(int bp) {
  final whole = bp ~/ 100;
  final part = bp % 100;
  if (part == 0) return '$whole%';
  final decimals = part % 10 == 0
      ? '${part ~/ 10}'
      : part.toString().padLeft(2, '0');
  return '$whole.$decimals%';
}

/// The part of a bill its card, wallet and QR tenders paid for, as a
/// fraction (see the library comment).
final class DigitalShare {
  const DigitalShare(this.numerator, this.denominator);

  /// Nothing paid digitally: the whole bill at the standard rate.
  static const none = DigitalShare(0, 1);

  /// All of it paid digitally: the whole bill at the reduced rate.
  static const all = DigitalShare(1, 1);

  /// The share a bill paid wholly by [mode] has: all of it for a card,
  /// none of it for cash or a bill with no tender yet.
  static DigitalShare wholly(ServiceTaxSetting? setting, String? mode) =>
      setting != null && mode != null && setting.isDigital(mode) ? all : none;

  final int numerator;
  final int denominator;

  bool get isNone => numerator == 0;
  bool get isAll => numerator == denominator;

  @override
  bool operator ==(Object other) =>
      other is DigitalShare &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => 'DigitalShare($numerator/$denominator)';
}

/// The share of the bill [tenders] pay digitally.
///
/// [totalAt] prices the bill at a given share, without its tenders; it is
/// how the share asks what the bill would come to if all of it went on the
/// card. Three cases:
///
///  * no service on the bill, no provincial tax, no reduced rate, or no
///    card, wallet or QR among the tenders: none of it;
///  * digital tenders that cover the whole bill at the reduced rate: all of
///    it (a card overpaying the bill is refused by the calculator, as any
///    non-cash overpayment is);
///  * otherwise the fraction of the bill they pay at their rate, `c / T`.
///    If that bill rounds below what was put on the card — only possible
///    when the card is within a rupee of the whole bill — the card has paid
///    the whole of it.
DigitalShare digitalShareFor({
  required ServiceTaxSetting? setting,
  required bool hasServices,
  required Iterable<({String mode, Money amount})> tenders,
  required Money Function(DigitalShare share) totalAt,
}) {
  if (setting == null || !hasServices || !setting.hasReducedRate) {
    return DigitalShare.none;
  }
  final digital = Money.sum([
    for (final t in tenders)
      if (setting.isDigital(t.mode) && t.amount.isPositive) t.amount,
  ]);
  if (!digital.isPositive) return DigitalShare.none;
  final whole = totalAt(DigitalShare.all);
  if (whole <= digital) return DigitalShare.all;
  final share = DigitalShare(digital.inPaisa, whole.inPaisa);
  if (totalAt(share) < digital) return DigitalShare.all;
  return share;
}

/// The provincial tax on one service line worth [value].
///
/// [value] is what the line comes to after its discounts — with the tax
/// inside it when [inclusive], which is the shop's own "prices include tax"
/// setting. The digital part is `value × share`, half up to the paisa; the
/// standard part is the rest, so the two always add back to [value]. Each
/// part is taxed at its own rate and rounded on its own, and each is its own
/// row. Nothing for a shop with no authority set: a service never carries
/// the federal 18%.
List<TaxCharge> serviceTaxCharges({
  required Money value,
  required ServiceTaxSetting? setting,
  required DigitalShare share,
  required bool inclusive,
}) {
  if (setting == null || !value.isPositive) return const [];
  final split = setting.hasReducedRate ? share : DigitalShare.none;
  final digitalPart = split.isAll
      ? value
      : split.isNone
      ? Money.zero
      : proRataShare(value, split.numerator, split.denominator);
  final charges = <TaxCharge>[];
  for (final (part, digital) in [
    (value - digitalPart, false),
    (digitalPart, true),
  ]) {
    final rate = digital ? setting.digitalBp : setting.standardBp;
    if (!part.isPositive || rate == 0) continue;
    final tax = inclusive ? taxInsidePrice(part, rate) : part.percentBp(rate);
    charges.add(
      TaxCharge(
        kind: TaxKind.provincialSt,
        code: setting.codeFor(digital: digital),
        rateBp: rate,
        base: inclusive ? part - tax : part,
        amount: tax,
        isInclusive: inclusive,
      ),
    );
  }
  return charges;
}
