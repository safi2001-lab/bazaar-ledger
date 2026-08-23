/// Asking a customer for money, in a message they will actually read.
///
/// Chasing udhaar is the work a khata exists for. A shopkeeper with forty
/// names in a book spends their evening on it, and the whole reason to move
/// the book onto a phone is that the phone can also send the message.
///
/// Nothing here talks to anybody. It builds a string and a phone number; the
/// app layer hands both to WhatsApp, which is already on the phone.
library;

import 'package:pk_money/pk_money.dart';

/// A Pakistani mobile number in the form WhatsApp addresses.
///
/// Shops write numbers however they like: `0300-4471203`, `0300 4471203`,
/// `+92 300 4471203`, `92-300-4471203`. WhatsApp wants `923004471203` — no
/// plus, no zero, no punctuation — and a number in any other shape opens a
/// chat with nobody.
///
/// Returns null when the digits cannot be a Pakistani mobile, rather than
/// guessing. A reminder sent to the wrong number is worse than one not sent:
/// it tells a stranger what somebody owes.
String? whatsappNumber(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  // Pakistani mobiles are 10 digits after the country code and always begin
  // with 3. Everything below normalises to that and then checks it, so a
  // landline or a half-typed number is refused rather than dialled.
  final national = switch (digits) {
    _ when digits.startsWith('92') => digits.substring(2),
    _ when digits.startsWith('0') => digits.substring(1),
    _ => digits,
  };

  if (national.length != 10) return null;
  if (!national.startsWith('3')) return null;
  return '92$national';
}

/// The reminder itself.
///
/// Roman Urdu, because that is what a shopkeeper's customers read, and
/// because it is what the shopkeeper would have typed. Short enough to fit a
/// notification preview: the ask has to survive being read on a lock screen.
///
/// Deliberately has no due date, no interest, and no threat. Pakistani law
/// has no thirty-day notice provision of the kind these apps like to invent,
/// and a shop that sends a legal-sounding message it cannot follow through on
/// has spent its relationship with a customer for nothing.
String reminderMessage({
  required String shopName,
  required String customerName,
  required Money balance,
  String? oldestBillDate,
}) {
  final buffer = StringBuffer()
    ..write('Assalam-o-Alaikum $customerName,\n\n')
    ..write('$shopName se: aap ka hisaab ${balance.amountOnly} rupay hai');

  if (oldestBillDate != null) {
    buffer.write(', jo $oldestBillDate se baqi hai');
  }

  buffer
    ..write('.\n\n')
    ..write('Meherbani farma kar jald ada kar dein. Shukriya.');

  return buffer.toString();
}
