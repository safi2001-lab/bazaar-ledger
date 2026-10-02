import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Purchase and sale orders, what has come of them, what to order, and an
/// order's advance on the bill made from it (M41), without a database.
void main() {
  final actor = ActorContext(
    firmId: 'F1',
    userId: 'U1',
    deviceId: 'D1',
    // 3 October 2026, mid-morning in Lahore.
    startedAtUtc: DateTime.utc(2026, 10, 3, 6),
  );
  const number = AllocatedNumber(
    formatted: 'PO-2627-0001',
    series: 'PO',
    sequence: 1,
  );

  OrderLineDraft line(
    String item,
    int qty,
    int rupees, {
    int base = 0,
    String unit = 'pcs',
  }) => OrderLineDraft(
    itemId: item,
    itemName: item,
    qty: Qty.units(qty),
    baseQty: Qty.units(base == 0 ? qty : base),
    unitId: unit,
    unitCode: unit,
    rate: Rate.rupees(rupees),
  );

  OrderLineProgress ordered(
    int lineNo,
    String item,
    int qty, {
    int base = 0,
    String unit = 'pcs',
    int rupees = 100,
    int done = 0,
  }) => OrderLineProgress(
    lineNo: lineNo,
    itemId: item,
    itemName: item,
    qty: Qty.units(qty),
    baseQty: Qty.units(base == 0 ? qty : base),
    unitId: unit,
    unitCode: unit,
    baseUnitCode: 'pcs',
    rate: Rate.rupees(rupees),
    done: Qty.units(done),
  );

  group('an order', () {
    const builder = OrderBuilder();

    test('is a document and its lines, with nothing paid and nothing owed', () {
      final posting = builder.build(
        actor: actor,
        number: number,
        draft: OrderDraft(
          kind: OrderKind.purchase,
          partyId: 'mill',
          partyName: 'Haji Flour Mills',
          lines: [
            line('atta', 10, 500),
            line('ghee', 2, 3600, base: 24, unit: 'ctn'),
          ],
          dueDate: const BusinessDate('2026-10-06'),
          notes: '  Subah bhejna ',
        ),
      );
      final doc = posting.document;
      expect(doc.docType, 'purchase_order');
      expect(doc.total, const Money.rupees(12200));
      expect(doc.paid, Money.zero);
      expect(doc.balance, Money.zero);
      expect(doc.tax, Money.zero);
      expect(doc.terms, 'Expected by 2026-10-06');
      expect(doc.notes, 'Subah bhejna');
      expect(orderDueDate(doc.terms), const BusinessDate('2026-10-06'));
      expect(posting.lines.last.baseQty, Qty.units(24));
      expect(posting.lines.last.unitCodeSnapshot, 'ctn');
      expect(posting.auditSummary, contains('Purchase order PO-2627-0001'));
    });

    test('a sale order is promised for its day', () {
      final doc = builder
          .build(
            actor: actor,
            number: number,
            draft: OrderDraft(
              kind: OrderKind.sale,
              partyId: 'aslam',
              lines: [line('ghee', 10, 500)],
              dueDate: const BusinessDate('2026-10-09'),
            ),
          )
          .document;
      expect(doc.docType, 'sale_order');
      expect(doc.terms, 'Promised for 2026-10-09');
    });

    test('needs somebody, something, a quantity, and a day not gone', () {
      OrderPosting build(OrderDraft d) =>
          builder.build(actor: actor, number: number, draft: d);
      expect(
        () => build(
          OrderDraft(
            kind: OrderKind.purchase,
            partyId: ' ',
            lines: [line('a', 1, 1)],
          ),
        ),
        throwsA(isA<OrderRefused>()),
      );
      expect(
        () => build(
          const OrderDraft(kind: OrderKind.sale, partyId: 'p', lines: []),
        ),
        throwsA(isA<OrderRefused>()),
      );
      expect(
        () => build(
          OrderDraft(
            kind: OrderKind.sale,
            partyId: 'p',
            lines: [line('a', 0, 1)],
          ),
        ),
        throwsA(isA<OrderRefused>()),
      );
      expect(
        () => build(
          OrderDraft(
            kind: OrderKind.purchase,
            partyId: 'p',
            lines: [line('a', 1, 1)],
            dueDate: const BusinessDate('2026-10-02'),
          ),
        ),
        throwsA(isA<OrderRefused>()),
      );
    });
  });

  group('what came of an order', () {
    test('is spread over its lines in order, the last line of an item '
        'taking any extra', () {
      final lines = spreadDone(
        [ordered(1, 'atta', 10), ordered(2, 'ghee', 5), ordered(3, 'atta', 4)],
        {'atta': Qty.units(16), 'ghee': Qty.units(2)},
      );
      expect(lines.map((l) => l.done), [
        Qty.units(10),
        Qty.units(2),
        Qty.units(6),
      ]);
      expect(lines.first.isDone, isTrue);
      expect(lines.last.pendingBase, Qty.zero);
      expect(orderStatusOf(isVoid: false, lines: lines), OrderStatus.part);
    });

    test('reads open, part, done, cancelled or closed', () {
      expect(
        orderStatusOf(isVoid: false, lines: [ordered(1, 'a', 2)]),
        OrderStatus.open,
      );
      expect(
        orderStatusOf(isVoid: false, lines: [ordered(1, 'a', 2, done: 2)]),
        OrderStatus.done,
      );
      expect(
        orderStatusOf(isVoid: true, lines: [ordered(1, 'a', 2)]),
        OrderStatus.cancelled,
      );
      expect(
        orderStatusOf(isVoid: true, lines: [ordered(1, 'a', 2, done: 1)]),
        OrderStatus.closed,
      );
      expect(OrderStatus.part.isStanding, isTrue);
      expect(OrderStatus.closed.isStanding, isFalse);
    });

    test('what is still to come is in cartons when it comes out whole, and '
        'in pieces when it does not', () {
      final whole = ordered(
        1,
        'ghee',
        2,
        base: 24,
        unit: 'ctn',
        rupees: 3600,
        done: 12,
      );
      expect(whole.pendingInOrderUnit, Qty.units(1));
      expect(whole.pendingValue, const Money.rupees(3600));
      final broken = ordered(
        1,
        'ghee',
        2,
        base: 24,
        unit: 'ctn',
        rupees: 3600,
        done: 7,
      );
      expect(broken.pendingInOrderUnit, isNull);
      expect(broken.pendingBase, Qty.units(17));
      expect(broken.baseRate, Rate.rupees(300));
      expect(broken.pendingValue, const Money.rupees(5100));
    });

    test('a delivery at a rate the order did not quote is flagged', () {
      expect(rateDiffers(Rate.rupees(520), Rate.rupees(500)), isTrue);
      expect(rateDiffers(Rate.rupees(500), Rate.rupees(500)), isFalse);
      expect(rateDiffers(Rate.rupees(520), null), isFalse);
    });
  });

  group('what to order', () {
    test('is what the shelf needs less what is on its way, and at least '
        'what a customer asked for', () {
      expect(
        orderToPlace(needed: Qty.units(9), onOrder: Qty.zero),
        Qty.units(9),
      );
      expect(
        orderToPlace(needed: Qty.units(9), onOrder: Qty.units(10)),
        Qty.zero,
      );
      expect(
        orderToPlace(needed: Qty.zero, onOrder: Qty.zero, asked: Qty.units(6)),
        Qty.units(6),
      );
      expect(
        orderToPlace(
          needed: Qty.units(2),
          onOrder: Qty.units(1),
          asked: Qty.units(6),
        ),
        Qty.units(5),
      );
    });

    test(
      'is grouped by the supplier each item last came from, nobody last',
      () {
        ReorderLine l(String name, String? supplier) => ReorderLine(
          itemId: name,
          itemName: name,
          unitId: 'pcs',
          unitCode: 'pcs',
          qty: Qty.units(2),
          supplierId: supplier,
          supplierName: supplier == null ? null : 'Supplier $supplier',
          rate: Rate.rupees(50),
        );
        final groups = groupBySupplier([
          l('Surf', 'B'),
          l('Atta', 'A'),
          l('Lux', null),
          l('Dal', 'A'),
        ]);
        expect(groups.map((g) => g.supplierName), [
          'Supplier A',
          'Supplier B',
          null,
        ]);
        expect(groups.first.lines.map((x) => x.itemName), ['Atta', 'Dal']);
        expect(groups.first.value, const Money.rupees(200));
        expect(groups.first.lines.first.toOrderLine().qty, Qty.units(2));
      },
    );

    test('a purchase order and the shortage list travel in words', () {
      final po = purchaseOrderMessage(
        shopName: 'Chishti Kiryana Store',
        docNo: 'PO-2627-0001',
        supplierName: 'Haji Sahib',
        due: const BusinessDate('2026-10-06'),
        notes: 'Subah',
        lines: [
          (
            name: 'Atta 10kg',
            qty: Qty.units(10),
            unit: 'bori',
            rate: Rate.rupees(500),
          ),
          (name: 'Namak', qty: Qty.units(2), unit: 'ctn', rate: Rate.zero),
        ],
      );
      expect(po, startsWith('Assalam-o-Alaikum Haji Sahib,'));
      expect(po, contains('Chishti Kiryana Store ka order PO-2627-0001:'));
      expect(po, contains('1. Atta 10kg: 10 bori @ Rs 500.00'));
      expect(po, contains('2. Namak: 2 ctn\n'));
      expect(po, contains('2026-10-06 tak bhej dein.'));
      expect(po, contains('Note: Subah'));

      final list = shortageMessage(
        shopName: 'Chishti',
        entries: [
          ShortageEntry(
            id: '1',
            name: 'Surf',
            qty: Qty.units(3),
            unitCode: 'pcs',
            addedOn: const BusinessDate('2026-10-03'),
          ),
          const ShortageEntry(
            id: '2',
            name: 'Kala namak',
            note: 'Bibi ne poocha',
            addedOn: BusinessDate('2026-10-03'),
          ),
        ],
      );
      expect(
        list,
        'Chishti: mangwana hai\n1. Surf: 3 pcs\n2. Kala namak (Bibi ne poocha)',
      );
    });
  });

  group('an order advance on its bill', () {
    SalePosting bill({Money paid = Money.zero}) {
      final total = const Money.rupees(5000);
      final owed = total - paid;
      return SalePosting(
        document: DocumentPosting(
          docType: 'sale_invoice',
          docNo: 'INV-2627-0009',
          docSeries: 'INV',
          docSeq: 9,
          fiscalYear: 2627,
          docDateUtcMillis: 0,
          docDateLocal: '2026-10-03',
          subtotal: total,
          lineDiscount: Money.zero,
          billDiscount: Money.zero,
          taxable: total,
          tax: Money.zero,
          furtherTax: Money.zero,
          withholding: Money.zero,
          extraCharges: Money.zero,
          roundOff: Money.zero,
          total: total,
          paid: paid,
          balance: owed,
          cost: Money.zero,
          roundingMode: 'half_up',
          taxRuleVersion: 'v0',
          cashThresholdBreached: false,
          partyId: 'aslam',
        ),
        lines: const [],
        payments: const [],
        stockMovements: const [],
        journal: JournalEntryPosting(
          entryNo: 'JV-1',
          entryDateUtcMillis: 0,
          entryDateLocal: '2026-10-03',
          fiscalYear: 2627,
          sourceType: 'sale',
          totalDebit: total,
          totalCredit: total,
          lines: [
            if (paid.isPositive)
              JournalLinePosting(
                lineNo: 1,
                accountSystemKey: '#cash',
                debit: paid,
                credit: Money.zero,
              ),
            if (owed.isPositive)
              JournalLinePosting(
                lineNo: 2,
                accountSystemKey: 'accounts_receivable',
                debit: owed,
                credit: Money.zero,
                partyId: 'aslam',
              ),
            JournalLinePosting(
              lineNo: 3,
              accountSystemKey: 'sales',
              debit: Money.zero,
              credit: total,
            ),
          ],
        ),
        auditSummary: 'Sale INV-2627-0009',
      );
    }

    test('moves what it covers off the udhaar onto the advance, and the '
        'bill reads that much paid', () {
      final out = withOrderAdvance(
        bill(),
        const Money.rupees(2000),
        orderNo: 'SO-2627-0001',
      );
      expect(out.document.paid, const Money.rupees(2000));
      expect(out.document.balance, const Money.rupees(3000));
      final byKey = {for (final l in out.journal.lines) l.accountSystemKey: l};
      expect(byKey['accounts_receivable']!.debit, const Money.rupees(3000));
      expect(byKey['customer_advances']!.debit, const Money.rupees(2000));
      expect(byKey['customer_advances']!.partyId, 'aslam');
      expect(out.journal.lines.map((l) => l.lineNo), [1, 2, 3]);
      expect(out.auditSummary, contains('advance 2,000.00 on SO-2627-0001'));
      out.assertBalanced();
    });

    test('never takes more than the bill leaves owed, and takes nothing '
        'from a bill paid at the counter', () {
      final out = withOrderAdvance(
        bill(paid: const Money.rupees(4000)),
        const Money.rupees(2500),
        orderNo: 'SO-1',
      );
      expect(out.document.paid, const Money.rupees(5000));
      expect(out.document.balance, Money.zero);
      expect(
        out.journal.lines.any(
          (l) => l.accountSystemKey == 'accounts_receivable',
        ),
        isFalse,
      );
      final paid = bill(paid: const Money.rupees(5000));
      expect(
        identical(
          withOrderAdvance(paid, const Money.rupees(100), orderNo: 'SO-1'),
          paid,
        ),
        isTrue,
      );
    });
  });
}
