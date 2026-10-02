import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// "Baqi chhor do": udhaar let go, as rows, before any of it is written
/// (M44).
void main() {
  final actor = ActorContext(
    firmId: 'firm',
    userId: 'owner',
    deviceId: 'counter',
    startedAtUtc: DateTime.utc(2026, 10, 3, 6),
  );
  const number = AllocatedNumber(
    formatted: 'WO-2627-0001',
    series: 'WO',
    sequence: 1,
  );
  const journal = AllocatedNumber(
    formatted: 'JV-2627-00009',
    series: 'JV',
    sequence: 9,
  );
  final bills = [
    OpenBill(
      documentId: 'b1',
      dateLocal: '2026-08-01',
      sequence: 1,
      outstanding: const Money.rupees(6000),
      docNo: 'INV-2627-0001',
    ),
    OpenBill(
      documentId: 'b2',
      dateLocal: '2026-09-01',
      sequence: 2,
      outstanding: const Money.rupees(4000),
      docNo: 'INV-2627-0002',
    ),
  ];

  ReceiptPosting build(
    AllowanceKind kind,
    int rupees, {
    String reason = 'Gahak chala gaya',
    int owed = 10000,
    List<String>? picked,
  }) => const AllowanceBuilder().build(
    actor: actor,
    draft: AllowanceDraft(
      partyId: 'aslam',
      kind: kind,
      amount: Money.rupees(rupees),
      reason: reason,
      documentIds: picked,
    ),
    openBills: bills,
    owed: Money.rupees(owed),
    paymentNumber: number,
    journalNumber: journal,
    ledgerAccountId: 'acct-expense',
    paymentAccountId: 'pay-adjust',
  );

  group('a write-off', () {
    test('debits the expense and credits the receivable, and balances', () {
      final posting = build(AllowanceKind.writeOff, 10000);
      final lines = posting.journal.lines;
      expect(lines.first.accountSystemKey, '#acct-expense');
      expect(lines.first.debit, const Money.rupees(10000));
      expect(lines[1].accountSystemKey, 'accounts_receivable');
      expect(lines[1].credit, const Money.rupees(10000));
      expect(posting.payment.mode, 'adjustment');
      expect(posting.payment.notes, 'Gahak chala gaya');
      expect(posting.auditAction, 'BAD_DEBT_WRITTEN_OFF');
      expect(posting.journal.narration, 'Written off WO-2627-0001');
      expect(
        [for (final s in posting.settlements) s.balance],
        [Money.zero, Money.zero],
      );
    });

    test('has to say why', () {
      expect(
        () => build(AllowanceKind.writeOff, 10000, reason: '  '),
        throwsA(isA<AllowanceRefused>()),
      );
    });

    test('lets go only what is owed', () {
      expect(
        () => build(AllowanceKind.writeOff, 12000),
        throwsA(isA<AllowanceRefused>()),
      );
    });

    test('of picked bills clears exactly those, in full', () {
      final posting = build(AllowanceKind.writeOff, 4000, picked: ['b2']);
      expect(posting.allocations.single.documentId, 'b2');
      expect(posting.allocations.single.mode, 'manual');
      expect(
        () => build(AllowanceKind.writeOff, 3000, picked: ['b2']),
        throwsA(isA<AllowanceRefused>()),
      );
    });

    test('of an opening balance clears it the way a receipt does', () {
      final posting = build(AllowanceKind.writeOff, 12500, owed: 12500);
      expect(posting.unapplied, const Money.rupees(2500));
      expect(posting.journal.lines.last.accountSystemKey, 'customer_advances');
      expect(posting.journal.lines.last.credit, const Money.rupees(2500));
    });
  });

  group('a settlement discount', () {
    test('goes oldest first and says what it is', () {
      final posting = build(AllowanceKind.settlementDiscount, 500, reason: '');
      expect(posting.allocations.single.documentId, 'b1');
      expect(posting.payment.notes, 'Settlement discount');
      expect(posting.auditAction, 'SETTLEMENT_DISCOUNT_GIVEN');
    });

    test('is known by its number', () {
      expect(
        AllowanceKind.ofPaymentNo('SD-2627-0001'),
        AllowanceKind.settlementDiscount,
      );
      expect(
        AllowanceKind.ofPaymentNo('WO-2627-B0007'),
        AllowanceKind.writeOff,
      );
      expect(AllowanceKind.ofPaymentNo('RCV-2627-0001'), isNull);
    });
  });

  group('who may let udhaar go', () {
    test('a cashier up to their ceiling, and no further', () {
      expect(
        settlementDiscountAllowed(
          role: Role.cashier,
          settled: const Money.rupees(10000),
          discount: const Money.rupees(500),
        ),
        isTrue,
      );
      expect(
        settlementDiscountAllowed(
          role: Role.cashier,
          settled: const Money.rupees(10000),
          discount: const Money.rupees(501),
        ),
        isFalse,
      );
    });

    test('whoever puts the books right, any amount, and a write-off', () {
      for (final role in [Role.owner, Role.manager, Role.accountant]) {
        expect(mayWriteOff(role), isTrue, reason: role.name);
        expect(
          settlementDiscountAllowed(
            role: role,
            settled: const Money.rupees(10000),
            discount: const Money.rupees(9000),
          ),
          isTrue,
          reason: role.name,
        );
      }
      expect(mayWriteOff(Role.cashier), isFalse);
    });
  });
}
