/// The customer's receipt, offered the moment money moves (M70).
///
/// Vyapar sends "transaction messages" for a sale, a purchase, a payment
/// in and a sale return, each with the party's balance after it, and its
/// users' complaint is not the message but that it arrives from Vyapar's
/// own number looking like spam. OkCredit sends one per khata entry from
/// the shop's own SIM, switchable per customer; what its users dislike is
/// a message with no off switch. Here the message is written in the
/// customer's own language (M39), says what moved and where the khata
/// stands now, and goes from the shopkeeper's own WhatsApp — opened on the
/// customer's chat with the words typed, Send pressed by a person. Nothing
/// here sends anything, and nothing in the app can: no SEND_SMS, no API.
///
/// Each customer is asked every time, has it opened by itself, or is never
/// offered one; the shop sets what a customer it never set is.
///
/// The Urdu-script words are data, as M39's template is: the app speaks
/// Roman Urdu and English, but a customer who reads Nastaliq is written to
/// in Nastaliq, and WhatsApp shapes it on their phone.
library;

import 'package:pk_money/pk_money.dart';

import 'reminder_templates.dart' show ReminderLanguage;

/// Whether a party is offered a receipt when money moves.
enum ReceiptOffer {
  /// "Har dafa poochhein": the confirmation offers to send it.
  ask,

  /// "Khud bhejein": WhatsApp opens on their chat with the message typed.
  /// The shopkeeper still presses Send; nothing goes in the background.
  auto,

  /// "Kabhi nahi": never offered.
  never;

  /// The choice kept as [name]; null for anything else, including the
  /// empty value that means "as the shop does".
  static ReceiptOffer? tryParse(String? name) {
    for (final o in values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// Where the shop keeps what a customer it never set is offered.
const receiptOfferDefaultKey = 'receipt.offer.default';

/// Where one party's own choice is kept. Empty is "as the shop does".
String receiptOfferPartyKey(String partyId) => 'receipt.offer.party.$partyId';

/// What kind of money moved.
enum MoneyMove {
  /// A bill saved at the counter.
  sale,

  /// Money taken against a customer's khata.
  received,

  /// Goods a customer brought back.
  saleReturn,

  /// Money paid to a supplier.
  paidSupplier;

  /// Whether the paper is a document (a bill, a return) rather than a
  /// payment, so its history is the document's.
  bool get isDocument => this == sale || this == saleReturn;
}

/// One movement of money, as the receipt for it needs it.
final class MoneyMoved {
  const MoneyMoved({
    required this.kind,
    required this.number,
    required this.amount,
    this.documentId,
    this.paymentId,
    this.paid = Money.zero,
    this.byCheque = false,
  }) : assert(documentId != null || paymentId != null);

  final MoneyMove kind;

  /// INV-…, RCPT-…, the return's number, the voucher's.
  final String number;

  /// The bill's total, the money taken or paid, the goods' value back.
  final Money amount;

  /// The bill or the return. Null for a payment.
  final String? documentId;

  /// The payment taken or made. Null for a bill or a return.
  final String? paymentId;

  /// Paid at the counter on a bill; handed back in money on a return.
  final Money paid;

  /// A cheque rather than money in hand: "cheque mil gaya", not "wusool".
  final bool byCheque;
}

/// The receipt for [event], to [name], from [shop], in [language], with
/// [balanceNow]: what the customer owes after it (negative when the shop
/// holds their money), or for a supplier what the shop still owes them.
///
/// Short enough for a lock screen: a greeting, what moved, where the khata
/// stands, thanks. Western digits in all three languages, as a bill prints
/// them.
String moneyReceiptMessage(
  MoneyMoved event, {
  required String name,
  required String shop,
  required Money balanceNow,
  required ReminderLanguage language,
}) {
  final w = _words[language]!;
  final lines = <String>[
    w.greet(name),
    switch (event.kind) {
      MoneyMove.sale => w.sale(shop, event.number, event.amount),
      MoneyMove.received =>
        event.byCheque
            ? w.chequeIn(shop, event.number, event.amount)
            : w.received(shop, event.number, event.amount),
      MoneyMove.saleReturn => w.returned(shop, event.number, event.amount),
      MoneyMove.paidSupplier =>
        event.byCheque
            ? w.chequeOut(shop, event.number, event.amount)
            : w.paidOut(shop, event.number, event.amount),
    },
    if (event.kind == MoneyMove.sale && event.paid.isPositive)
      w.paidNow(event.paid),
    if (event.kind == MoneyMove.saleReturn && event.paid.isPositive)
      w.refunded(event.paid),
    if (event.kind == MoneyMove.paidSupplier)
      balanceNow.isPositive ? w.weOwe(balanceNow) : w.settled
    else if (balanceNow.isPositive)
      w.owes(balanceNow)
    else if (balanceNow.isNegative)
      w.credit(-balanceNow)
    else
      w.clear,
    w.thanks,
  ];
  return lines.join('\n');
}

/// One language's sentences.
final class _Words {
  const _Words({
    required this.greet,
    required this.sale,
    required this.received,
    required this.chequeIn,
    required this.returned,
    required this.paidOut,
    required this.chequeOut,
    required this.paidNow,
    required this.refunded,
    required this.owes,
    required this.credit,
    required this.clear,
    required this.weOwe,
    required this.settled,
    required this.thanks,
  });

  final String Function(String name) greet;
  final String Function(String shop, String no, Money amount) sale;
  final String Function(String shop, String no, Money amount) received;
  final String Function(String shop, String no, Money amount) chequeIn;
  final String Function(String shop, String no, Money amount) returned;
  final String Function(String shop, String no, Money amount) paidOut;
  final String Function(String shop, String no, Money amount) chequeOut;
  final String Function(Money paid) paidNow;
  final String Function(Money refund) refunded;
  final String Function(Money owed) owes;
  final String Function(Money held) credit;
  final String clear;
  final String Function(Money owed) weOwe;
  final String settled;
  final String thanks;
}

String _rs(Money m) => 'Rs ${m.amountOnly}';
String _rupay(Money m) => '${m.amountOnly} روپے';

final _words = <ReminderLanguage, _Words>{
  ReminderLanguage.romanUrdu: _Words(
    greet: (name) => 'Assalam-o-Alaikum $name,',
    sale: (shop, no, a) => '$shop: bill $no, kul ${_rs(a)}.',
    received: (shop, no, a) => '$shop: ${_rs(a)} wusool ho gaye, raseed $no.',
    chequeIn: (shop, no, a) =>
        '$shop: ${_rs(a)} ka cheque mil gaya, raseed $no.',
    returned: (shop, no, a) => '$shop: maal wapas liya, $no, ${_rs(a)}.',
    paidOut: (shop, no, a) =>
        '$shop ki taraf se ${_rs(a)} ada kiye, voucher $no.',
    chequeOut: (shop, no, a) =>
        '$shop ki taraf se ${_rs(a)} ka cheque diya, voucher $no.',
    paidNow: (p) => 'Ada kiye: ${_rs(p)}.',
    refunded: (r) => 'Wapas diye: ${_rs(r)}.',
    owes: (o) => 'Aap ka kul baqaya ab: ${_rs(o)}.',
    credit: (h) => 'Aap ki raqam hamare paas jama: ${_rs(h)}.',
    clear: 'Aap ka hisaab saaf hai.',
    weOwe: (o) => 'Hamara baqaya ab: ${_rs(o)}.',
    settled: 'Hisaab saaf.',
    thanks: 'Shukriya.',
  ),
  ReminderLanguage.english: _Words(
    greet: (name) => 'Assalam-o-Alaikum $name,',
    sale: (shop, no, a) => '$shop: bill $no, total ${_rs(a)}.',
    received: (shop, no, a) => '$shop: received ${_rs(a)}, receipt $no.',
    chequeIn: (shop, no, a) =>
        '$shop: received a cheque for ${_rs(a)}, receipt $no.',
    returned: (shop, no, a) => '$shop: goods returned, $no, ${_rs(a)}.',
    paidOut: (shop, no, a) => '$shop: paid you ${_rs(a)}, voucher $no.',
    chequeOut: (shop, no, a) =>
        '$shop: a cheque to you for ${_rs(a)}, voucher $no.',
    paidNow: (p) => 'Paid: ${_rs(p)}.',
    refunded: (r) => 'Refunded: ${_rs(r)}.',
    owes: (o) => 'Your balance now: ${_rs(o)}.',
    credit: (h) => 'In credit with us: ${_rs(h)}.',
    clear: 'Your account is clear.',
    weOwe: (o) => 'We now owe you: ${_rs(o)}.',
    settled: 'Account settled.',
    thanks: 'Thank you.',
  ),
  ReminderLanguage.urdu: _Words(
    greet: (name) => 'السلام علیکم $name،',
    sale: (shop, no, a) => '$shop: بل $no، کل ${_rupay(a)}۔',
    received: (shop, no, a) => '$shop: ${_rupay(a)} وصول ہو گئے، رسید $no۔',
    chequeIn: (shop, no, a) => '$shop: ${_rupay(a)} کا چیک مل گیا، رسید $no۔',
    returned: (shop, no, a) => '$shop: مال واپس لیا، $no، ${_rupay(a)}۔',
    paidOut: (shop, no, a) =>
        '$shop کی طرف سے ${_rupay(a)} ادا کیے، واؤچر $no۔',
    chequeOut: (shop, no, a) =>
        '$shop کی طرف سے ${_rupay(a)} کا چیک دیا، واؤچر $no۔',
    paidNow: (p) => 'ادا کیے: ${_rupay(p)}۔',
    refunded: (r) => 'واپس دیے: ${_rupay(r)}۔',
    owes: (o) => 'آپ کا کل بقایا اب: ${_rupay(o)}۔',
    credit: (h) => 'آپ کی رقم ہمارے پاس جمع: ${_rupay(h)}۔',
    clear: 'آپ کا حساب صاف ہے۔',
    weOwe: (o) => 'ہمارا بقایا اب: ${_rupay(o)}۔',
    settled: 'حساب صاف۔',
    thanks: 'شکریہ۔',
  ),
};
