import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Asking a customer for money.
///
/// Chasing udhaar is the work a khata exists for, and the whole reason to
/// move the book onto a phone is that the phone can also send the message.
void main() {
  group('the number WhatsApp needs', () {
    test('however the shop wrote it down', () {
      // Every one of these is a real shape a shopkeeper types.
      for (final written in [
        '0300-4471203',
        '0300 4471203',
        '03004471203',
        '+92 300 4471203',
        '92-300-4471203',
        '+923004471203',
        '3004471203',
        ' 0300 447 1203 ',
      ]) {
        expect(whatsappNumber(written), '923004471203', reason: written);
      }
    });

    test('every network prefix, not only the common one', () {
      for (final prefix in ['30', '31', '32', '33', '34', '35']) {
        expect(whatsappNumber('0${prefix}04471203'), '92${prefix}04471203');
      }
    });

    test('nothing at all is nothing, not an empty chat', () {
      expect(whatsappNumber(null), isNull);
      expect(whatsappNumber(''), isNull);
      expect(whatsappNumber('   '), isNull);
      expect(whatsappNumber('-'), isNull);
    });

    test('a half-typed number is refused rather than dialled', () {
      // A reminder sent to the wrong number is worse than one not sent: it
      // tells a stranger what somebody owes.
      expect(whatsappNumber('0300'), isNull);
      expect(whatsappNumber('030044712'), isNull);
      expect(whatsappNumber('030044712034'), isNull);
    });

    test('a landline is refused', () {
      // 042 is Lahore. WhatsApp cannot reach it, and trying opens a chat with
      // a number that is not the customer.
      expect(whatsappNumber('042-35761234'), isNull);
      expect(whatsappNumber('021-34567890'), isNull);
    });
  });

  group('the message', () {
    test('names the shop, the customer and the amount', () {
      final message = reminderMessage(
        shopName: 'Chishti Kiryana Store',
        customerName: 'Rashid Sahib',
        balance: const Money.rupees(4500),
      );

      expect(message, contains('Rashid Sahib'));
      expect(message, contains('Chishti Kiryana Store'));
      expect(message, contains('4,500.00'));
    });

    test('says since when, when the shop knows', () {
      final message = reminderMessage(
        shopName: 'Chishti Kiryana Store',
        customerName: 'Rashid Sahib',
        balance: const Money.rupees(4500),
        oldestBillDate: '2026-06-01',
      );

      expect(message, contains('2026-06-01'));
    });

    test('and does not invent one when it does not', () {
      final message = reminderMessage(
        shopName: 'Shop',
        customerName: 'Rashid',
        balance: const Money.rupees(100),
      );

      expect(message, isNot(contains('se baqi')));
    });

    test('threatens nothing, and cites no law', () {
      // Pakistani law has no thirty-day notice provision of the kind these
      // apps like to invent, and a shop that sends a legal-sounding message
      // it cannot follow through on has spent its relationship with a
      // customer for nothing. `no_invented_legal_notice` guards the same
      // thing at the source level.
      final message = reminderMessage(
        shopName: 'Shop',
        customerName: 'Rashid',
        balance: const Money.rupees(100),
      ).toLowerCase();

      for (final word in [
        '30 day',
        '30 din',
        'legal',
        'qanoon',
        'court',
        'adalat',
        'notice',
        'police',
        'interest',
        'sood',
      ]) {
        expect(message, isNot(contains(word)), reason: word);
      }
    });

    test('is short enough to survive a lock screen', () {
      // The ask has to be readable in a notification preview, or it is read
      // for the first time inside the app, which is one tap the shopkeeper
      // does not control.
      final message = reminderMessage(
        shopName: 'Chishti Kiryana Store',
        customerName: 'Rashid Sahib',
        balance: const Money.rupees(4500),
        oldestBillDate: '2026-06-01',
      );

      expect(message.length, lessThan(220));
    });

    test('greets in the form this market actually uses', () {
      expect(
        reminderMessage(
          shopName: 'Shop',
          customerName: 'Rashid',
          balance: const Money.rupees(100),
        ),
        startsWith('Assalam-o-Alaikum'),
      );
    });
  });
}
