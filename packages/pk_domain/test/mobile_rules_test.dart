import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The mobile-shop pack's pure rules (M50): the IMEI check digit, the CNIC's
/// form, the day a warranty ends, a qist schedule and how a receipt pays it
/// off.
void main() {
  group('the IMEI', () {
    test(
      'the Luhn check digit catches a digit typed wrong and two swapped',
      () {
        expect(imeiProblem('356938035643809'), isNull);
        expect(imeiProblem('35-693803-564380-9'), isNull, reason: 'as printed');
        final wrong = imeiProblem('356938035643808')!;
        expect(wrong.kind, ImeiProblemKind.checkDigit);
        expect(wrong.expectedLast, 9);
        expect(wrong.words, contains('should be 9'));
        // Two neighbours swapped: 69 typed as 96.
        expect(
          imeiProblem('359638035643809')?.kind,
          ImeiProblemKind.checkDigit,
        );
        expect(
          imeiProblem('35693803564380')?.kind,
          ImeiProblemKind.wrongLength,
        );
        expect(imeiProblem('35693803564380X')?.kind, ImeiProblemKind.notDigits);
        expect(imeiProblem('  ')?.kind, ImeiProblemKind.empty);
      },
    );

    test('a dual-SIM phone names two different IMEIs', () {
      const PhoneUnitDraft(
        imei1: '356938035643809',
        imei2: '356938035643817',
      ).check();
      const PhoneUnitDraft(imei1: '356938035643809', imei2: '').check();
      expect(
        () => const PhoneUnitDraft(
          imei1: '356938035643809',
          imei2: '356938035643809',
        ).check(),
        throwsA(isA<ImeiRefused>()),
      );
    });

    test('the PTA check is an SMS of the IMEI to 8484, typed and not sent', () {
      final sms = ptaCheckSms('35-693803-564380-9');
      expect(sms.scheme, 'sms');
      expect(sms.path, '8484');
      expect(sms.queryParameters['body'], '356938035643809');
      expect(PtaStatus.fromCode('non_compliant')!.mayBeBlocked, isTrue);
      expect(PtaStatus.approved.printed, 'PTA Approved');
    });
  });

  test('a CNIC is thirteen digits, with or without its dashes', () {
    expect(cnicWellFormed('35202-1234567-1'), isTrue);
    expect(cnicWellFormed('3520212345671'), isTrue);
    expect(cnicWellFormed('35202-12345671'), isFalse);
    expect(cnicWellFormed('3520-21234567-1'), isFalse);
    expect(cnicDisplay(cnicDigits('35202 1234567 1')), '35202-1234567-1');
  });

  test("a warranty ends the same day of the month, or that month's last", () {
    expect(warrantyEndsOn(BusinessDate('2026-04-03'), 12).value, '2027-04-03');
    expect(warrantyEndsOn(BusinessDate('2026-01-31'), 1).value, '2026-02-28');
    expect(warrantyEndsOn(BusinessDate('2027-12-31'), 2).value, '2028-02-29');
    expect(printedDate(BusinessDate('2027-04-03')), '3 Apr 2027');
  });

  group('qist', () {
    test('a schedule is whole rupees, the remainder on the last, never a '
        'paisa out', () {
      final schedule = scheduleInstalments(
        financed: Money.rupees(50001),
        count: 10,
        firstDue: BusinessDate('2026-11-30'),
        dueDay: 30,
      );
      expect(schedule.length, 10);
      expect(schedule.first.amount, Money.rupees(5000));
      expect(schedule.last.amount, Money.rupees(5001));
      expect(
        Money.sum([for (final i in schedule) i.amount]),
        Money.rupees(50001),
      );
      expect(schedule[1].dueOn.value, '2026-12-30');
      expect(schedule[3].dueOn.value, '2027-02-28', reason: 'February');
      expect(schedule[4].dueOn.value, '2027-03-30', reason: 'and back');
      expect(firstDueAfter(BusinessDate('2026-10-03'), 5).value, '2026-11-05');
    });

    test('a receipt pays the oldest instalment first', () {
      final schedule = scheduleInstalments(
        financed: Money.rupees(15000),
        count: 3,
        firstDue: BusinessDate('2026-11-05'),
        dueDay: 5,
      );
      final standings = settleOldestFirst(schedule, Money.rupees(7000));
      expect(standings[0].isPaid, isTrue);
      expect(standings[1].paid, Money.rupees(2000));
      expect(standings[2].paid, Money.zero);
      final today = BusinessDate('2026-12-06');
      expect(standings[1].isOverdueOn(today), isTrue);
      expect(standings[2].isOverdueOn(today), isFalse);
      // Closed early on 20 November: everything left is due that day.
      final closed = settleOldestFirst(
        schedule,
        Money.rupees(7000),
        closedOn: BusinessDate('2026-11-20'),
      );
      expect(closed[2].dueOn.value, '2026-11-20');
      expect(closed[0].dueOn.value, '2026-11-05', reason: 'already past');
    });

    test('a plan that does not fit its bill is refused in words', () {
      QistPosting post({
        String? party = 'P1',
        int total = 60000,
        int paid = 10000,
        int count = 10,
        String first = '2026-11-05',
        Guarantor? guarantor,
      }) => postQist(
        QistPlanDraft(
          count: count,
          dueDay: 5,
          firstDue: BusinessDate(first),
          guarantor: guarantor,
        ),
        partyId: party,
        soldOn: BusinessDate('2026-10-03'),
        total: Money.rupees(total),
        paid: Money.rupees(paid),
        markup: Money.zero,
      );
      expect(post().financed, Money.rupees(50000));
      expect(() => post(party: null), throwsA(isA<QistRefused>()));
      expect(() => post(paid: 60000), throwsA(isA<QistRefused>()));
      expect(() => post(count: 61), throwsA(isA<QistRefused>()));
      expect(() => post(first: '2026-10-03'), throwsA(isA<QistRefused>()));
      expect(
        () => post(
          guarantor: const Guarantor(name: 'Tariq', cnic: '123'),
        ),
        throwsA(isA<QistRefused>()),
      );
    });
  });
}
