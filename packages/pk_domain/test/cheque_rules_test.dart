import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The rules a cheque carries before any lifecycle exists: the day it can be
/// banked, and who wrote it.
void main() {
  group('the day a cheque can be banked', () {
    test('a date survives being stored, whatever side of midnight', () {
      // Stored as 00:00 PKT, which is 19:00 the previous day in UTC. A naive
      // conversion reads it back a day early.
      for (final date in ['2026-09-30', '2026-12-31', '2027-01-01']) {
        final due = BusinessDate(date);
        expect(chequeDueDate(chequeDueUtcMillis(due)), due);
      }
    });

    test('days until it is due count calendar days, and go negative', () {
      const today = BusinessDate('2026-09-26');
      expect(daysUntil(today, const BusinessDate('2026-09-26')), 0);
      expect(daysUntil(today, const BusinessDate('2026-10-26')), 30);
      expect(daysUntil(today, const BusinessDate('2026-09-20')), -6);
    });
  });

  group('a cheque at the counter', () {
    const builder = SalePostingBuilder();
    const calculator = SaleCalculator();
    const untaxed = TaxContext(
      isSellerRegistered: false,
      buyerIsRegistered: false,
      buyerIsOnAtl: null,
      province: 'punjab',
      pricesIncludeTax: false,
      ruleVersion: 'untaxed-v1',
    );

    SalePosting post({String? partyId, String? chequeNo}) {
      final draft = SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: 'I-oil',
            itemName: 'Oil',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: 'PA-CHQ',
            mode: 'cheque',
            amount: const Money.rupees(2500),
            chequeNo: chequeNo,
          ),
        ],
      );
      return builder.build(
        actor: ActorContext(
          firmId: 'F1',
          userId: 'U1',
          deviceId: 'D1',
          startedAtUtc: DateTime.utc(2026, 9, 26, 9, 15),
        ),
        draft: draft,
        calculated: calculator.calculate(draft, untaxed),
        invoiceNumber: const AllocatedNumber(
          formatted: 'INV-2627-0001',
          series: 'INV',
          sequence: 1,
        ),
        journalNumber: const AllocatedNumber(
          formatted: 'JV-2627-00001',
          series: 'JV',
          sequence: 1,
        ),
        paymentNumbers: const [
          AllocatedNumber(
            formatted: 'RCV-2627-0001',
            series: 'RCV',
            sequence: 1,
          ),
        ],
        ledgerAccountByPaymentAccount: const {'PA-CHQ': 'ACC-CHQ'},
      );
    }

    test('goes to Cheques in Hand, not the bank', () {
      final posting = post(partyId: 'P1', chequeNo: '004512');
      final line = posting.journal.lines.firstWhere((l) => l.debit.isPositive);
      expect(line.accountSystemKey, 'cheques_in_hand');
    });

    test('with no number is refused before the schema has to', () {
      expect(() => post(partyId: 'P1'), throwsArgumentError);
      expect(() => post(partyId: 'P1', chequeNo: '  '), throwsArgumentError);
    });

    test(
      'from a walk-in is refused, since a bounce would have nobody to chase',
      () {
        expect(() => post(chequeNo: '004512'), throwsArgumentError);
      },
    );
  });
}
