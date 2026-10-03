import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The recovery man's sheet and goods given rate-later, as values, before
/// any of it is written (M55).
void main() {
  SheetLine line(int no, String name, int owed, {List<int> bills = const []}) =>
      SheetLine(
        lineNo: no,
        partyId: 'p$no',
        partyName: name,
        due: Money.rupees(owed),
        bills: [
          for (final (i, b) in bills.indexed)
            SheetBill(
              documentId: 'd$no$i',
              docNo: 'INV-2627-000$i',
              dateLocal: '2026-09-1$i',
              outstanding: Money.rupees(b),
            ),
        ],
      );

  final sheet = CollectionSheet(
    id: 'sheet1',
    sheetNo: 'WS-2627-0001',
    dateLocal: '2026-10-03',
    collector: 'Rafiq',
    madeBy: 'Malik Sahib',
    title: 'Route 3',
    lines: [
      line(1, 'Aslam Karyana', 5000, bills: [3000]),
      line(2, 'Bilal Store', 3000, bills: [1000, 2000]),
      line(3, 'Chaudhry Traders', 2000),
      line(4, 'Dawood Mart', 1000),
      line(5, 'Ehsan Bros', 800),
    ],
  );

  group('a collection sheet', () {
    test('owes what the khata said, the bills behind it and the rest from '
        'before', () {
      expect(sheet.expected, const Money.rupees(11800));
      expect(sheet.lines.first.earlier, const Money.rupees(2000));
      expect(sheet.lines[1].earlier, Money.zero);
      expect(sheet.lines[2].earlier, const Money.rupees(2000));
      expect(sheet.isSettled, isFalse);
      expect(sheet.collected, Money.zero);
      expect(sheet.notReached, 5);
    });

    test('settled: what came, the cash to hand over and what was promised', () {
      final marks = {
        1: const SheetMark(
          outcome: CollectionOutcome.paid,
          paymentAccountId: 'cash',
        ),
        2: const SheetMark(
          outcome: CollectionOutcome.partial,
          amount: Money.rupees(1000),
          mode: 'jazzcash',
          paymentAccountId: 'wallet',
        ),
        3: const SheetMark(
          outcome: CollectionOutcome.promise,
          promisedFor: '2026-10-09',
          amount: Money.rupees(2000),
        ),
        4: const SheetMark(outcome: CollectionOutcome.shopClosed),
      };
      final settled = sheet.settled(
        on: '2026-10-03',
        by: 'Malik Sahib',
        lines: [
          for (final l in sheet.lines)
            l.withResult(marks[l.lineNo]?.resultFor(l)),
        ],
      );
      expect(settled.collected, const Money.rupees(6000));
      expect(settled.cashToHandOver, const Money.rupees(5000));
      expect(settled.promised, const Money.rupees(2000));
      expect(settled.count(CollectionOutcome.paid), 1);
      expect(settled.count(CollectionOutcome.shopClosed), 1);
      expect(settled.notReached, 1);
      // A promise and a closed shop took no money and name no account.
      expect(settled.lines[2].result!.received, Money.zero);
      expect(settled.lines[2].result!.paymentAccountId, isNull);
    });

    test('is kept as JSON and read back whole', () {
      final settled = sheet.settled(
        on: '2026-10-03',
        by: 'Malik Sahib',
        lines: [
          for (final l in sheet.lines)
            l.withResult(
              l.lineNo == 1
                  ? const SheetMark(
                      outcome: CollectionOutcome.paid,
                      paymentAccountId: 'cash',
                      note: 'beta dukaan par tha',
                    ).resultFor(l).written(paymentNo: 'RCV-2627-0001')
                  : null,
            ),
        ],
      );
      final back = CollectionSheet.fromJson(
        'sheet1',
        jsonDecode(jsonEncode(settled.toJson())),
      )!;
      expect(back.sheetNo, 'WS-2627-0001');
      expect(back.collector, 'Rafiq');
      expect(back.title, 'Route 3');
      expect(back.settledBy, 'Malik Sahib');
      expect(back.expected, settled.expected);
      expect(back.collected, const Money.rupees(5000));
      expect(back.lines[1].bills.last.docNo, 'INV-2627-0001');
      expect(back.lines.first.result!.paymentNo, 'RCV-2627-0001');
      expect(back.lines.first.result!.note, 'beta dukaan par tha');
      expect(CollectionSheet.fromJson('x', 'not a sheet'), isNull);
    });

    test('a mark is refused in words when it cannot be written', () {
      final aslam = sheet.lines.first;
      const today = '2026-10-03';
      expect(
        const SheetMark(
          outcome: CollectionOutcome.partial,
          paymentAccountId: 'cash',
        ).problemFor(aslam, today),
        contains('write what came in'),
      );
      expect(
        const SheetMark(
          outcome: CollectionOutcome.paid,
          mode: 'cheque',
          paymentAccountId: 'cheques',
        ).problemFor(aslam, today),
        contains('cheque'),
      );
      expect(
        const SheetMark(
          outcome: CollectionOutcome.promise,
          promisedFor: '2026-10-01',
        ).problemFor(aslam, today),
        contains('today or a day to come'),
      );
      expect(
        const SheetMark(
          outcome: CollectionOutcome.paid,
          paymentAccountId: 'cash',
        ).problemFor(aslam, today),
        isNull,
      );
      expect(
        const SheetMark(
          outcome: CollectionOutcome.refused,
        ).problemFor(aslam, today),
        isNull,
      );
      expect(
        const SheetDraft(partyIds: ['a', 'a'], collector: 'Rafiq').problem,
        contains('twice'),
      );
      expect(
        const SheetDraft(partyIds: ['a'], collector: ' ').problem,
        contains('Name the man'),
      );
    });
  });

  group('goods given rate later', () {
    test('every line goes at no rate and no discount; the goods, the units '
        'and the customer stay', () {
      final draft = SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: 'ghee',
            itemName: 'Ghee',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: 'kg',
            unitCode: 'kg',
            rate: Rate.rupees(600),
            discountBp: 500,
          ),
          SaleLineDraft(
            itemId: 'atta',
            itemName: 'Atta',
            qty: Qty.units(1),
            baseQty: Qty.units(40),
            unitId: 'maund',
            unitCode: 'maund',
            rate: Rate.rupees(4000),
          ),
        ],
        partyId: 'aslam',
        partyName: 'Aslam Karyana',
        billDiscount: const Money.rupees(100),
      );
      final later = rateLater(draft);
      expect([for (final l in later.lines) l.rate], [Rate.zero, Rate.zero]);
      expect([for (final l in later.lines) l.discountBp], [0, 0]);
      expect(later.lines.last.baseQty, Qty.units(40));
      expect(later.lines.last.unitCode, 'maund');
      expect(later.partyId, 'aslam');
      expect(later.billDiscount, Money.zero);
    });

    test('a line at no rate waits for one; a free item does not', () {
      final given = GoodsGiven(
        challanId: 'c1',
        docNo: 'CHL-2627-0001',
        dateLocal: '2026-10-01',
        lines: [
          GoodsGivenLine(
            itemId: 'ghee',
            itemName: 'Ghee',
            qty: Qty.units(10),
            unitCode: 'kg',
            rate: Rate.zero,
          ),
          GoodsGivenLine(
            itemId: 'soap',
            itemName: 'Soap',
            qty: Qty.units(1),
            unitCode: 'pcs',
            rate: Rate.zero,
            isFree: true,
          ),
          GoodsGivenLine(
            itemId: 'cheeni',
            itemName: 'Cheeni',
            qty: Qty.units(5),
            unitCode: 'kg',
            rate: Rate.rupees(160),
          ),
        ],
      );
      expect(given.unpricedCount, 1);
      expect(given.waitsForRate, isTrue);
      expect(given.pricedValue, const Money.rupees(800));
    });
  });
}
