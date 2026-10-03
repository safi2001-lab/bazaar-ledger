import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A sale posting copied carries everything it was not told to change
/// (found by M49).
///
/// `SalePosting.copyWith` rebuilt the posting from a list of fields, and the
/// list had missed `replacesId`: a bill putting a cancelled one right (M36)
/// that was also made from a sale order with an advance (M41) went through
/// `withOrderAdvance`, came out without the cancelled bill's id, and was
/// written with no `revises` link to it.
void main() {
  const rx = Prescription(
    patientName: 'Bilal Ahmed',
    prescriberName: 'Dr Ayesha Khan',
    prescriberRegNo: '12345-P',
  );

  DocumentPosting document({Money balance = const Money.rupees(500)}) =>
      DocumentPosting(
        docType: 'sale_invoice',
        docNo: 'INV-2627-0009',
        docSeries: 'INV',
        docSeq: 9,
        fiscalYear: 2627,
        docDateUtcMillis: 1,
        docDateLocal: '2026-10-03',
        subtotal: const Money.rupees(500),
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: const Money.rupees(500),
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: const Money.rupees(500),
        paid: Money.zero,
        balance: balance,
        cost: Money.zero,
        roundingMode: 'half_up',
        taxRuleVersion: 'v0',
        cashThresholdBreached: false,
        partyId: 'PTY1',
      );

  SalePosting posting() => SalePosting(
    document: document(),
    lines: const [
      DocumentLinePosting(
        lineNo: 1,
        itemId: 'ITM1',
        itemNameSnapshot: 'Xanax 0.5',
        qty: Qty.one,
        baseQty: Qty.one,
        unitCodeSnapshot: 'pcs',
        rate: Rate.rupees(500),
        gross: Money.rupees(500),
        discount: Money.zero,
        taxable: Money.rupees(500),
        tax: Money.zero,
        lineTotal: Money.rupees(500),
        cost: Money.zero,
        discountBp: 0,
        isFreeItem: false,
        taxes: [],
      ),
    ],
    payments: const [],
    stockMovements: const [
      StockMovementPosting(
        itemId: 'ITM1',
        txnType: 'sale',
        qtyDelta: Qty.raw(-1000),
        valueDelta: Money.zero,
        occurredAtUtcMillis: 1,
        occurredOnLocal: '2026-10-03',
        lineNo: 1,
      ),
    ],
    journal: const JournalEntryPosting(
      entryNo: 'JV-2627-0009',
      entryDateUtcMillis: 1,
      entryDateLocal: '2026-10-03',
      fiscalYear: 2627,
      sourceType: 'sale',
      totalDebit: Money.rupees(500),
      totalCredit: Money.rupees(500),
      lines: [
        JournalLinePosting(
          lineNo: 1,
          accountSystemKey: 'accounts_receivable',
          debit: Money.rupees(500),
          credit: Money.zero,
          partyId: 'PTY1',
        ),
        JournalLinePosting(
          lineNo: 2,
          accountSystemKey: 'sales',
          debit: Money.zero,
          credit: Money.rupees(500),
        ),
      ],
    ),
    auditSummary: 'Sale INV-2627-0009',
    convertedFromId: 'SO1',
    alsoFromIds: const ['CH2'],
    replacesId: 'INV-OLD',
    prescription: rx,
  );

  void expectCarried(SalePosting copy, SalePosting from) {
    expect(copy.lines, same(from.lines));
    expect(copy.payments, same(from.payments));
    expect(copy.stockMovements, same(from.stockMovements));
    expect(copy.convertedFromId, from.convertedFromId);
    expect(copy.alsoFromIds, from.alsoFromIds);
    expect(copy.replacesId, from.replacesId);
    expect(copy.prescription, same(from.prescription));
  }

  group('a sale posting copied', () {
    test('carries every part it was not told to change', () {
      final from = posting();
      final copy = from.copyWith(auditSummary: 'changed');
      expect(copy.auditSummary, 'changed');
      expect(copy.document, same(from.document));
      expect(copy.journal, same(from.journal));
      expectCarried(copy, from);
      expect(copy.replacesId, 'INV-OLD');
    });

    test('a bill putting another right, made from a sale order with an '
        'advance, keeps the bill it replaces', () {
      final from = posting();
      final settled = withOrderAdvance(
        from,
        const Money.rupees(200),
        orderNo: 'SO-2627-0001',
      );
      expect(settled.document.balance, const Money.rupees(300));
      expect(
        settled.replacesId,
        'INV-OLD',
        reason: 'the revises link the writer makes from it',
      );
      expectCarried(settled, from);
    });

    test('replaces what it is told to', () {
      final copy = posting().copyWith(
        replacesId: 'INV-OTHER',
        alsoFromIds: const <String>[],
      );
      expect(copy.replacesId, 'INV-OTHER');
      expect(copy.alsoFromIds, isEmpty);
      expect(copy.convertedFromId, 'SO1');
    });
  });
}
