/// A phone's numbers, and what PTA says of it (M50).
///
/// A mobile shop lives by the IMEI. It is the number a stolen phone is
/// reported by, the number PTA blocks a phone by, and the number a customer
/// back with a dead screen is found by. M11 already kept every phone as a
/// lot of its own named by its serial; this file is what makes that serial
/// an IMEI: checked when it is typed, its second number for the other SIM
/// slot, the PTA standing the shop found out, and the day its warranty ends.
///
/// ## The check digit
///
/// An IMEI is fifteen digits, and the fifteenth is a Luhn check digit over
/// the first fourteen (3GPP TS 23.003, Annex B — the same scheme as a bank
/// card's last digit). One digit typed wrong, or two neighbours swapped,
/// gives a number whose last digit does not match, so a mistyped IMEI is
/// caught at the counter rather than on the day the police ask for it. The
/// check proves only that the number is well formed; whether such a phone
/// exists, or is blocked, is PTA's to say.
library;

import '../time/clock.dart';

/// [raw] with the spaces, dashes, slashes and dots people type between the
/// groups taken out: "35-693803-564380-9" is "356938035643809".
String imeiDigits(String raw) => raw.replaceAll(RegExp(r'[\s\-/.]'), '');

/// The Luhn check digit for [body], a run of digits (the first fourteen of
/// an IMEI).
int luhnCheckDigit(String body) {
  var sum = 0;
  // Counted from the right of the body: the digit next to where the check
  // digit goes is doubled, and every second one after it.
  for (var i = 0; i < body.length; i++) {
    var d = body.codeUnitAt(body.length - 1 - i) - 0x30;
    if (i.isEven) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return (10 - sum % 10) % 10;
}

/// Whether [digits] (all digits) ends in the right Luhn check digit.
bool luhnValid(String digits) {
  if (digits.length < 2 || !RegExp(r'^\d+$').hasMatch(digits)) return false;
  final body = digits.substring(0, digits.length - 1);
  return luhnCheckDigit(body) == digits.codeUnitAt(digits.length - 1) - 0x30;
}

/// Why a number typed as an IMEI is not one.
enum ImeiProblemKind {
  /// Nothing was typed.
  empty,

  /// Something other than digits.
  notDigits,

  /// Not fifteen digits.
  wrongLength,

  /// Fifteen digits whose last does not match the first fourteen.
  checkDigit,

  /// IMEI 2 typed as the same number as IMEI 1.
  sameAsFirst,
}

/// A number refused as an IMEI, with what the screen needs to say why in
/// the shopkeeper's language.
final class ImeiProblem {
  const ImeiProblem(this.kind, this.digits, {this.expectedLast});

  final ImeiProblemKind kind;

  /// What was typed, with the separators taken out.
  final String digits;

  /// For [ImeiProblemKind.checkDigit], the last digit the first fourteen
  /// call for — said, so the shopkeeper can see which of the two numbers on
  /// the box he misread.
  final int? expectedLast;

  /// The refusal in English, for a refusal raised beneath the screens.
  String get words => switch (kind) {
    ImeiProblemKind.empty =>
      'Type the IMEI: 15 digits, printed on the box and shown by dialling '
          '*#06#.',
    ImeiProblemKind.notDigits =>
      'An IMEI is digits only, and "$digits" is not.',
    ImeiProblemKind.wrongLength =>
      'An IMEI is 15 digits, and $digits has ${digits.length}.',
    ImeiProblemKind.checkDigit =>
      'IMEI $digits is mistyped: its last digit should be $expectedLast for '
          'the fourteen before it. Copy it again from the box or from *#06#.',
    ImeiProblemKind.sameAsFirst =>
      'IMEI 2 is the same number as IMEI 1. A dual-SIM phone has two '
          'different numbers; leave IMEI 2 empty for a single-SIM phone.',
  };

  @override
  String toString() => words;
}

/// Why [raw] is not an IMEI, or null when it is one.
ImeiProblem? imeiProblem(String raw) {
  final d = imeiDigits(raw);
  if (d.isEmpty) return ImeiProblem(ImeiProblemKind.empty, d);
  if (!RegExp(r'^\d+$').hasMatch(d)) {
    return ImeiProblem(ImeiProblemKind.notDigits, d);
  }
  if (d.length != 15) return ImeiProblem(ImeiProblemKind.wrongLength, d);
  if (!luhnValid(d)) {
    return ImeiProblem(
      ImeiProblemKind.checkDigit,
      d,
      expectedLast: luhnCheckDigit(d.substring(0, 14)),
    );
  }
  return null;
}

/// Thrown when a number given as an IMEI is not one, beneath every screen.
final class ImeiRefused implements Exception {
  const ImeiRefused(this.problem);

  final ImeiProblem problem;

  @override
  String toString() => problem.words;
}

// ---------------------------------------------------------------------------
// CNIC
// ---------------------------------------------------------------------------

/// [raw] with the dashes and spaces taken out: "35202-1234567-1" is
/// "3520212345671".
String cnicDigits(String raw) => raw.replaceAll(RegExp(r'[\s\-]'), '');

/// Whether [raw] is a CNIC in form: thirteen digits, with or without the
/// dashes in their places (5-7-1).
///
/// The form only. NADRA's own check of whether such a card was issued is a
/// service this app does not call; nothing here leaves the phone.
bool cnicWellFormed(String raw) {
  final t = raw.trim();
  return RegExp(r'^\d{13}$').hasMatch(t) ||
      RegExp(r'^\d{5}-\d{7}-\d$').hasMatch(t);
}

/// "35202-1234567-1" from thirteen digits; anything else as it came.
String cnicDisplay(String digits) => RegExp(r'^\d{13}$').hasMatch(digits)
    ? '${digits.substring(0, 5)}-${digits.substring(5, 12)}-'
          '${digits.substring(12)}'
    : digits;

// ---------------------------------------------------------------------------
// PTA
// ---------------------------------------------------------------------------

/// What PTA's Device Identification, Registration and Blocking System
/// (DIRBS) says of a phone's IMEI, as the shop found it out.
///
/// The three answers are the ones the PTA check gives back, as reported by
/// ProPakistani (2018) and Daily Capital; this app has not read PTA's own
/// rules and does not claim to: **[the statuses and the 60-day blocking are
/// unverified against PTA's own pages]**. The shop asks — an SMS of the IMEI
/// to 8484 from its own phone — and writes the answer down here.
enum PtaStatus {
  /// Registered with PTA: works on every network.
  approved('approved'),

  /// A real phone, brought in without PTA registration (an informal
  /// import). Reported to work for a while on the SIM first used in it.
  validUnapproved('valid_unapproved'),

  /// Not a valid IMEI to DIRBS — copied, cloned, or never issued. Reported
  /// to be blocked within sixty days.
  nonCompliant('non_compliant'),

  /// Not asked yet, or the answer was not written down.
  unknown('unknown');

  const PtaStatus(this.code);

  /// What the database stores.
  final String code;

  static PtaStatus? fromCode(String? code) =>
      values.where((s) => s.code == code).firstOrNull;

  /// What the bill prints, in the English every bill is printed in.
  String get printed => switch (this) {
    approved => 'PTA Approved',
    validUnapproved => 'Valid, not PTA approved',
    nonCompliant => 'PTA Non-compliant',
    unknown => 'PTA not checked',
  };

  /// Whether selling it is a sale the counter should warn about: the
  /// customer pays for a phone PTA may block.
  bool get mayBeBlocked => this == nonCompliant;
}

/// The number PTA answers an IMEI check on, by SMS. About ten paisa a
/// message, from any network **[as reported, unverified]**.
const ptaCheckNumber = '8484';

/// An `sms:` link that opens the phone's own messages app with [imei] typed
/// to 8484, ready for the shopkeeper to press Send.
///
/// Nothing is sent by this app: it holds no SEND_SMS permission (Play
/// reserves it for SMS apps), calls no server, and reads no reply. The
/// answer comes back as an ordinary message, and the shopkeeper writes it
/// down.
Uri ptaCheckSms(String imei) => Uri(
  scheme: 'sms',
  path: ptaCheckNumber,
  queryParameters: {'body': imeiDigits(imei)},
);

// ---------------------------------------------------------------------------
// Warranty
// ---------------------------------------------------------------------------

/// Whose warranty an item carries.
enum WarrantyKind {
  /// The shop's own promise: brought back here.
  shop('shop'),

  /// The maker's official warranty, honoured at its service centre.
  brand('brand');

  const WarrantyKind(this.code);

  final String code;

  static WarrantyKind? fromCode(String? code) =>
      values.where((k) => k.code == code).firstOrNull;
}

/// How long an item's warranty runs, and whose it is.
final class ItemWarranty {
  const ItemWarranty({required this.months, this.kind = WarrantyKind.shop});

  /// No warranty: what an item that never had one is saved as.
  static const none = ItemWarranty(months: 0);

  /// 1 to 120; zero is none.
  final int months;
  final WarrantyKind kind;

  bool get isNone => months <= 0;

  @override
  bool operator ==(Object other) =>
      other is ItemWarranty &&
      (other.isNone && isNone || other.months == months && other.kind == kind);

  @override
  int get hashCode => isNone ? 0 : Object.hash(months, kind);
}

/// The last day a warranty of [months] months on goods sold on [sold] runs.
///
/// The same day of the month, [months] later — a phone sold on 3 April 2026
/// with a year's warranty is covered until 3 April 2027 — or that month's
/// last day when it has no such day (sold on 31 January, a month's warranty
/// runs to 28 or 29 February).
BusinessDate warrantyEndsOn(BusinessDate sold, int months) =>
    addMonthsClamped(sold, months, sold.day);

/// [from] moved [months] months on, on [day] of that month or its last day
/// when it is shorter.
BusinessDate addMonthsClamped(BusinessDate from, int months, int day) {
  final index = from.year * 12 + (from.month - 1) + months;
  final year = index ~/ 12;
  final month = index % 12 + 1;
  final last = DateTime.utc(year, month + 1, 0).day;
  final d = day < 1 ? 1 : (day > last ? last : day);
  return BusinessDate(
    '${year.toString().padLeft(4, '0')}-'
    '${month.toString().padLeft(2, '0')}-'
    '${d.toString().padLeft(2, '0')}',
  );
}

/// `3 Apr 2027`: how the bill says a warranty's last day.
String printedDate(BusinessDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// ---------------------------------------------------------------------------
// A phone as it comes in
// ---------------------------------------------------------------------------

/// One phone on a delivery or bought over the counter: its IMEIs, and what
/// PTA said of it when the shop checked.
final class PhoneUnitDraft {
  const PhoneUnitDraft({
    required this.imei1,
    this.imei2,
    this.pta = PtaStatus.unknown,
  });

  /// The IMEI the phone is kept by: SIM slot 1.
  final String imei1;

  /// The second SIM slot's, on a dual-SIM phone.
  final String? imei2;

  final PtaStatus pta;

  /// [imei1] and [imei2] as digits, the second only when given.
  List<String> get imeis => [
    imeiDigits(imei1),
    if (imei2 case final second? when imeiDigits(second).isNotEmpty)
      imeiDigits(second),
  ];

  /// Refuses a mistyped IMEI, or IMEI 2 typed as IMEI 1, in words.
  void check() {
    if (imeiProblem(imei1) case final problem?) throw ImeiRefused(problem);
    final second = imei2;
    if (second == null || imeiDigits(second).isEmpty) return;
    if (imeiProblem(second) case final problem?) throw ImeiRefused(problem);
    if (imeiDigits(second) == imeiDigits(imei1)) {
      throw ImeiRefused(
        ImeiProblem(ImeiProblemKind.sameAsFirst, imeiDigits(second)),
      );
    }
  }
}
