import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Reminders in the customer's own language (M39).
///
/// The words are the owner's to change, so what is asserted here is the
/// machinery around them — every placeholder filled, a line with nothing to
/// say left out rather than sent half-empty — and that the words the shop
/// starts with keep the rules the first reminder kept (M3): a greeting, the
/// shop and the amount, a kind ask, no threat, no law, and short enough to
/// read on a lock screen.
void main() {
  const facts = ReminderFacts(
    name: 'Aslam Karyana',
    amount: Money.rupees(4500),
    shop: 'Chishti Kiryana Store',
    dueDateLocal: '2026-09-16',
    oldestBillDateLocal: '2026-09-01',
    shopPhone: '0300 1234567',
    wallet: 'Raast 03001234567',
  );

  group('a template', () {
    test('has every placeholder filled from the khata', () {
      final message = fillReminder(
        '{name}|{amount}|{due}|{shop}|{phone}|{wallet}|{oldest_bill_date}',
        facts,
        ReminderLanguage.romanUrdu,
      );
      expect(
        message,
        'Aslam Karyana|4,500.00|16 Sep|Chishti Kiryana Store|0300 1234567|'
        'Raast 03001234567|1 Sep',
      );
    });

    test('leaves out a line that would say nothing', () {
      const bare = ReminderFacts(
        name: 'Naseem',
        amount: Money.rupees(2500),
        shop: 'Chishti Kiryana Store',
      );
      final message = fillReminder(
        defaultReminderTemplate(ReminderLanguage.romanUrdu),
        bare,
        ReminderLanguage.romanUrdu,
      );
      expect(message, isNot(contains('{')));
      expect(message, isNot(contains('Adaygi:')));
      expect(message, isNot(contains('Rabta:')));
      expect(message, contains('Rs 2,500.00'));
      expect(message.split('\n').where((l) => l.isEmpty), isEmpty);
    });

    test('leaves anything else in braces as the owner typed it', () {
      expect(
        fillReminder('{name} {bonus}', facts, ReminderLanguage.english),
        'Aslam Karyana {bonus}',
      );
    });

    test('says dates the way each language reads them', () {
      expect(reminderDate('2026-10-09', ReminderLanguage.english), '9 Oct');
      expect(reminderDate('2026-10-09', ReminderLanguage.romanUrdu), '9 Oct');
      expect(reminderDate('2026-10-09', ReminderLanguage.urdu), '9 اکتوبر');
    });
  });

  group('the shop words', () {
    for (final language in ReminderLanguage.values) {
      test('in ${language.name} greet, name the shop and the amount, and '
          'ask kindly', () {
        final message = fillReminder(
          defaultReminderTemplate(language),
          facts,
          language,
        );
        expect(message, contains('Aslam Karyana'));
        expect(message, contains('Chishti Kiryana Store'));
        expect(message, contains('4,500.00'));
        expect(message, contains('Raast 03001234567'));
        expect(
          message,
          anyOf(contains('Assalam-o-Alaikum'), contains('السلام علیکم')),
        );
        expect(message, isNot(contains('{')));
      });

      test('in ${language.name} threaten nothing and cite no law', () {
        final message = fillReminder(
          defaultReminderTemplate(language),
          facts,
          language,
        ).toLowerCase();
        for (final word in [
          'legal',
          'court',
          'police',
          'action',
          'qanooni',
          'karwai',
          'adalat',
          'عدالت',
          'قانونی',
          'کارروائی',
        ]) {
          expect(message, isNot(contains(word)), reason: word);
        }
      });

      test('in ${language.name} are short enough for a lock screen', () {
        final message = fillReminder(
          defaultReminderTemplate(language),
          facts,
          language,
        );
        expect(message.length, lessThan(320));
      });
    }

    test('in Urdu are written in Urdu script', () {
      final message = defaultReminderTemplate(ReminderLanguage.urdu);
      expect(RegExp('[؀-ۿ]').allMatches(message).length, greaterThan(60));
    });
  });

  group('a customer', () {
    test('reads Roman Urdu until told otherwise, and is reminded', () {
      expect(ReminderPrefs.standard.language, ReminderLanguage.romanUrdu);
      expect(ReminderPrefs.standard.optedOut, isFalse);
      expect(ReminderLanguage.parse('nonsense'), ReminderLanguage.romanUrdu);
    });

    test('keeps a language and an opt-out across a save', () {
      const prefs = ReminderPrefs(
        language: ReminderLanguage.urdu,
        optedOut: true,
      );
      expect(ReminderPrefs.fromJson(prefs.toJson()), prefs);
    });
  });

  group("the shop's payment details", () {
    test('are its Raast alias and its bank account, as plain text', () {
      expect(
        walletLine(
          raastAlias: '03001234567',
          bankName: 'Meezan Bank',
          accountTitle: 'Chishti Kiryana',
          iban: 'PK36MEZN0001234567890101',
        ),
        'Raast 03001234567 · Meezan Bank PK36MEZN0001234567890101 '
        '(Chishti Kiryana)',
      );
      expect(walletLine(raastAlias: ' '), isNull);
      expect(
        walletLine(iban: 'PK36MEZN0001234567890101'),
        'Bank PK36MEZN0001234567890101',
      );
    });
  });
}
