/// Reminders in the customer's own language, from templates the owner can
/// change (M39).
///
/// A shop with forty names to chase writes to some of them in Urdu, some in
/// Roman Urdu and a few in English, and until now every reminder went out in
/// the one Roman Urdu sentence `reminderMessage` builds. Here each language
/// has a template, the owner edits the words in Settings (and can put the
/// shop's own back with one tap), each customer has a language and can be
/// left alone altogether, and the placeholders fill from the khata.
///
/// The Urdu-script template is data, not a string in the app's language
/// files: the app itself speaks Roman Urdu and English, but a message sent
/// to a customer who reads Nastaliq is written in Nastaliq. WhatsApp shapes
/// it on the customer's phone, in their font; nothing here renders it.
///
/// The defaults keep the rules the first reminder kept (M3): they greet,
/// they name the shop and the amount, they ask kindly, they threaten
/// nothing and cite no law, and they are short enough to be read on a lock
/// screen.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';
import 'aging.dart';
import 'due_dates.dart';

/// The languages a reminder goes out in.
enum ReminderLanguage {
  /// Urdu in its own script, for the customer who reads the newspaper in it.
  urdu('ur'),

  /// Roman Urdu, which is what most of this market types on a phone.
  romanUrdu('roman'),

  /// English.
  english('en');

  const ReminderLanguage(this.code);

  /// How it is kept in the settings rows.
  final String code;

  /// The language kept as [code]; Roman Urdu when unknown, because that is
  /// what every reminder was before languages existed.
  static ReminderLanguage parse(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return romanUrdu;
  }
}

/// Every placeholder a template may use. Anything else in braces is left
/// as typed.
const reminderPlaceholders = [
  '{name}',
  '{amount}',
  '{due}',
  '{shop}',
  '{phone}',
  '{wallet}',
  '{oldest_bill_date}',
];

/// Where a language's template is kept in the shop's settings.
String reminderTemplateKey(ReminderLanguage language) =>
    'reminder.template.${language.code}';

/// Where one customer's reminder language and opt-out are kept.
String reminderPrefsKey(String partyId) => 'reminder.party.$partyId';

/// The shop's own words for each language, used until the owner writes
/// theirs and again after "back to the shop's words".
String defaultReminderTemplate(ReminderLanguage language) => switch (language) {
  ReminderLanguage.urdu => _urdu,
  ReminderLanguage.romanUrdu => _roman,
  ReminderLanguage.english => _english,
};

const _roman = '''
Assalam-o-Alaikum {name},
{shop} se yaad-dehani: aap ka hisaab Rs {amount} hai.
Pehla baqi bill {oldest_bill_date} ka hai, adaygi ki tareekh {due}.
Adaygi: {wallet}
Meherbani farma kar jald ada kar dein. Shukriya.
Rabta: {phone}''';

const _english = '''
Assalam-o-Alaikum {name},
A gentle reminder from {shop}: your balance is Rs {amount}.
Oldest bill {oldest_bill_date}, due {due}.
Pay to: {wallet}
Kindly clear it at your convenience. Thank you.
Contact: {phone}''';

const _urdu = '''
السلام علیکم {name}،
{shop} کی طرف سے یاد دہانی: آپ کا حساب {amount} روپے ہے۔
پہلا بقایا بل {oldest_bill_date} کا ہے، ادائیگی کی تاریخ {due}۔
ادائیگی: {wallet}
مہربانی فرما کر جلد ادا کر دیں۔ شکریہ۔
رابطہ: {phone}''';

/// What a reminder says about one customer.
final class ReminderFacts {
  const ReminderFacts({
    required this.name,
    required this.amount,
    required this.shop,
    this.dueDateLocal,
    this.oldestBillDateLocal,
    this.shopPhone,
    this.wallet,
  });

  final String name;
  final Money amount;
  final String shop;

  /// The day the oldest open bill fell (or falls) due.
  final String? dueDateLocal;
  final String? oldestBillDateLocal;
  final String? shopPhone;

  /// The shop's payment details, from [walletLine].
  final String? wallet;
}

/// [template] with [facts] in it, for a customer who reads [language].
///
/// A line whose placeholder has nothing to say is left out whole, rather
/// than sent as "Adaygi: " with nothing after it: a shop with no IBAN, a
/// customer whose only debt is an opening balance with no bill to date it.
String fillReminder(
  String template,
  ReminderFacts facts,
  ReminderLanguage language,
) {
  String? day(String? ymd) => ymd == null ? null : reminderDate(ymd, language);
  final values = <String, String?>{
    '{name}': facts.name,
    '{amount}': facts.amount.amountOnly,
    '{due}': day(facts.dueDateLocal),
    '{shop}': facts.shop,
    '{phone}': facts.shopPhone,
    '{wallet}': facts.wallet,
    '{oldest_bill_date}': day(facts.oldestBillDateLocal),
  };
  final kept = <String>[];
  for (final line in template.split('\n')) {
    var text = line;
    var empty = false;
    for (final MapEntry(:key, :value) in values.entries) {
      if (!text.contains(key)) continue;
      final said = (value ?? '').trim();
      if (said.isEmpty) {
        empty = true;
        break;
      }
      text = text.replaceAll(key, said);
    }
    if (!empty) kept.add(text.trimRight());
  }
  // No blank line at either end, and never two in a row.
  final out = <String>[];
  for (final line in kept) {
    if (line.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

/// A date as a reminder in [language] says it: `9 Oct` in Roman Urdu and
/// English, `9 اکتوبر` in Urdu script. Western digits in all three, which is
/// how dates are printed in Pakistan's Urdu newspapers and on its bills.
String reminderDate(String ymd, ReminderLanguage language) {
  if (language != ReminderLanguage.urdu) return shortDate(ymd);
  final date = BusinessDate.tryParse(ymd);
  if (date == null) return ymd;
  return '${date.day} ${_urduMonths[date.month - 1]}';
}

const _urduMonths = [
  'جنوری',
  'فروری',
  'مارچ',
  'اپریل',
  'مئی',
  'جون',
  'جولائی',
  'اگست',
  'ستمبر',
  'اکتوبر',
  'نومبر',
  'دسمبر',
];

/// The shop's payment details as one line for `{wallet}`: its Raast alias
/// (which any bank app, JazzCash or Easypaisa can pay) and its bank account
/// — the same plain text the receipt prints, never a payment link or a QR
/// payload. Null when the shop has set neither.
String? walletLine({
  String? raastAlias,
  String? bankName,
  String? accountTitle,
  String? iban,
}) {
  String? clean(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
  final parts = <String>[
    if (clean(raastAlias) case final alias?) 'Raast $alias',
    if (clean(iban) case final account?)
      [
        clean(bankName) ?? 'Bank',
        account,
        if (clean(accountTitle) case final title?) '($title)',
      ].join(' '),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// How a reminder left the phone.
enum ReminderChannel {
  /// Into the customer's WhatsApp chat, typed and waiting for Send.
  whatsapp,

  /// Into the phone's own messages app, typed and waiting for Send. The
  /// shopkeeper taps Send; the app never holds the SMS permission.
  sms,

  /// Through the share sheet, to wherever the shopkeeper chose.
  share;

  static ReminderChannel parse(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => share);
}

/// A customer's reminder settings.
final class ReminderPrefs {
  const ReminderPrefs({
    this.language = ReminderLanguage.romanUrdu,
    this.optedOut = false,
  });

  factory ReminderPrefs.fromJson(Map<String, Object?> json) => ReminderPrefs(
    language: ReminderLanguage.parse(json['language'] as String?),
    optedOut: json['opt_out'] == true,
  );

  /// The language their reminders are written in.
  final ReminderLanguage language;

  /// They asked not to be reminded ("mujhe message na karein"), or the shop
  /// decided not to. Left off the bulk queue and the khata's Remind.
  final bool optedOut;

  Map<String, Object?> toJson() => {
    'language': language.code,
    'opt_out': optedOut,
  };

  static const standard = ReminderPrefs();

  @override
  bool operator ==(Object other) =>
      other is ReminderPrefs &&
      other.language == language &&
      other.optedOut == optedOut;

  @override
  int get hashCode => Object.hash(language, optedOut);
}

/// One reminder sent, as the khata's log keeps it.
final class ReminderSent {
  const ReminderSent({
    required this.partyId,
    required this.atUtc,
    required this.byName,
    required this.channel,
    required this.language,
  });

  final String partyId;
  final DateTime atUtc;

  /// Who at the shop sent it.
  final String byName;
  final ReminderChannel channel;
  final ReminderLanguage language;

  /// Whole business days between when it was sent and [today].
  int daysAgo(String today) =>
      daysBetween(BusinessDate.fromUtc(atUtc).value, today);
}
