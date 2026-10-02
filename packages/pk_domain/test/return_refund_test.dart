import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// What a return gives back (M57): exactly what the line was charged, in
/// proportion to what comes back, in the unit it was sold in.
///
/// The line is priced by the real [SaleCalculator] and read back the way
/// the database read does — its total, its discount, its taxes, its cost —
/// so these are the figures a return actually starts from.
void main() {
  const builder = ReturnBuilder();
  final actor = ActorContext(
    firmId: 'firm-1',
    userId: 'user-1',
    deviceId: 'device-1',
    startedAtUtc: DateTime.utc(2026, 10, 3, 6),
  );
  const number = AllocatedNumber(
    formatted: 'SRN-2627-0001',
    series: 'SRN',
    sequence: 1,
  );
  const journal = AllocatedNumber(
    formatted: 'JV-2627-00001',
    series: 'JV',
    sequence: 1,
  );

  ReturnPosting giveBack(SoldLine line, Qty qty, {String? partyId = 'P1'}) =>
      builder.build(
        actor: actor,
        draft: ReturnDraft(
          originalDocumentId: 'DOC-1',
          reason: 'Wapas',
          refundNow: partyId == null ? line.shareOf(qty).refund : Money.zero,
          paymentAccountId: partyId == null ? 'PA-CASH' : null,
          lines: [
            ReturnLineDraft(documentLineId: line.documentLineId, qty: qty),
          ],
        ),
        soldLines: [line],
        originalDocNo: 'INV-2627-0001',
        partyId: partyId,
        originalOutstanding: const Money.rupees(10000000),
        returnNumber: number,
        journalNumber: journal,
        refundLedgerAccountId: 'ACC-CASH',
      );

  JournalLinePosting? on(ReturnPosting p, String key) {
    for (final l in p.journal.lines) {
      if (l.accountSystemKey == key) return l;
    }
    return null;
  }

  group('what comes back', () {
    test('a line with 10% off comes back at the Rs 900 paid, not Rs 1,000', () {
      final line = _sold(
        _line(qty: Qty.units(10), rate: Rate.rupees(100), discountBp: 1000),
      );
      expect(line.charged, const Money.rupees(900));

      final whole = giveBack(line, Qty.units(10));
      expect(whole.document.total, const Money.rupees(900));

      final one = giveBack(line, Qty.one);
      expect(one.document.total, const Money.rupees(90));
    });

    test('its share of a discount on the whole bill comes back with it', () {
      final sale = const SaleCalculator().calculate(
        SaleDraft(
          billDiscount: const Money.rupees(60),
          lines: [
            _line(qty: Qty.units(3), rate: Rate.rupees(100)),
            _line(qty: Qty.units(6), rate: Rate.rupees(50), id: 'ITEM-2'),
          ],
        ),
        _untaxed,
      );
      final soap = _soldFrom(sale.lines.first);
      expect(soap.charged, const Money.rupees(270));
      expect(giveBack(soap, Qty.one).document.total, const Money.rupees(90));
    });

    test('a maund is counted, offered and taken back in maunds', () {
      // One maund of atta at Rs 5,000 is forty kilos on the shelf.
      final line = _sold(
        _line(
          qty: Qty.one,
          baseQty: Qty.units(40),
          rate: Rate.rupees(5000),
          unitCode: 'maund',
        ),
      );
      expect(line.returnable, Qty.one, reason: 'offered as 40 maund');
      expect(line.returnableBase, Qty.units(40));

      final half = giveBack(line, Qty.parse('0.5'));
      expect(half.document.total, const Money.rupees(2500));
      expect(half.lines.single.qty, Qty.parse('0.5'));
      expect(half.lines.single.baseQty, Qty.units(20));
      expect(half.lines.single.unitCodeSnapshot, 'maund');
      expect(half.lines.single.rate, Rate.rupees(5000));
      expect(half.stockMovements.single.qtyDelta, Qty.units(20));

      expect(
        () => giveBack(line, Qty.units(40)),
        throwsA(isA<ReturnRefused>()),
        reason: 'forty maunds off a bill for one is the Rs 2,00,000 refund',
      );
    });

    test('a dozen comes back as twelve pieces on the shelf', () {
      final line = _sold(
        _line(
          qty: Qty.units(2),
          baseQty: Qty.units(24),
          rate: Rate.rupees(300),
          discountBp: 1000,
          unitCode: 'dozen',
        ),
      );
      final one = giveBack(line, Qty.one);
      expect(one.document.total, const Money.rupees(270));
      expect(one.stockMovements.single.qtyDelta, Qty.units(12));
    });

    test('a part that does not come out even on the shelf is refused', () {
      // A tola is 11.664 grams, and a thousandth of a tola is not a whole
      // number of thousandths of a gram.
      final line = _sold(
        _line(
          qty: Qty.one,
          baseQty: Qty.raw(11664),
          rate: Rate.rupees(250000),
          unitCode: 'tola',
        ),
      );
      expect(() => line.shareOf(Qty.raw(1)), throwsA(isA<ReturnRefused>()));
      expect(line.shareOf(Qty.raw(125)).baseQty, Qty.raw(1458));
      expect(line.shareOf(Qty.one).baseQty, Qty.raw(11664));
    });

    test('what an awkward earlier return left still comes back whole', () {
      // Seven kilos off a maund, taken back before returns counted in the
      // unit sold: 0.825 maund is left, and taking all of it empties the
      // line to the gram.
      final line = SoldLine(
        documentLineId: 'L1',
        itemId: 'ITEM-1',
        itemName: 'Atta',
        unitId: 'U-MAUND',
        unitCode: 'maund',
        qty: Qty.one,
        soldQty: Qty.units(40),
        alreadyReturned: Qty.parse('7.001'),
        rate: Rate.rupees(5000),
        cost: const Money.rupees(4400),
      );
      expect(line.returnable, Qty.parse('0.824'));
      final rest = line.shareOf(line.returnable);
      expect(rest.baseQty, Qty.parse('32.999'));
      expect(
        rest.refund,
        const Money.rupees(5000) -
            returnedShare(
              const Money.rupees(5000),
              before: 0,
              taking: 7001,
              outOf: 40000,
            ),
      );
    });
  });

  group('part returns of one line', () {
    test('the first return is its own part, rounded once, half up', () {
      final line = SoldLine(
        documentLineId: 'L1',
        itemId: 'ITEM-1',
        itemName: 'Sabun',
        unitId: 'U-PCS',
        unitCode: 'pcs',
        soldQty: Qty.units(3),
        alreadyReturned: Qty.zero,
        rate: Rate.rupees(4),
        charged: const Money.paisa(1000),
        cost: Money.zero,
      );
      expect(line.shareOf(Qty.one).refund, const Money.paisa(333));
      expect(line.shareOf(Qty.units(2)).refund, const Money.paisa(667));
    });

    test(
      'Rs 299.99 across three soaps comes back as 100.00, 99.99, 100.00',
      () {
        var line = SoldLine(
          documentLineId: 'L1',
          itemId: 'ITEM-1',
          itemName: 'Sabun',
          unitId: 'U-PCS',
          unitCode: 'pcs',
          soldQty: Qty.units(3),
          alreadyReturned: Qty.zero,
          rate: Rate.rupees(100),
          charged: const Money.paisa(29999),
          discount: const Money.paisa(1),
          cost: Money.zero,
        );
        final refunds = <Money>[];
        for (var i = 0; i < 3; i++) {
          final share = line.shareOf(Qty.one);
          refunds.add(share.refund);
          line = _after(line, share);
        }
        expect(refunds, const [
          Money.paisa(10000),
          Money.paisa(9999),
          Money.paisa(10000),
        ]);
      },
    );

    test(
      'property: any run of part returns adds up to the line to the paisa',
      () {
        final random = Random(57);
        const factors = [1000, 12000, 24000, 40000];
        for (var run = 0; run < 2000; run++) {
          final factor = factors[random.nextInt(factors.length)];
          final registered = random.nextBool();
          final context = TaxContext(
            isSellerRegistered: registered,
            buyerIsRegistered: random.nextBool(),
            buyerIsOnAtl: random.nextBool(),
            province: 'Punjab',
            pricesIncludeTax: random.nextBool(),
            ruleVersion: 'pk-2026-27-v1',
            hasNamedBuyer: random.nextBool(),
          );
          final lines = [
            for (var i = 0; i < 1 + random.nextInt(3); i++)
              () {
                final qty = Qty.raw(1000 + random.nextInt(49000));
                return _line(
                  id: 'ITEM-$i',
                  qty: qty,
                  baseQty: Qty.raw(qty.inThousandths * factor ~/ 1000),
                  // Rs 1 to Rs 10,000 a unit, to the milli-paisa.
                  rate: Rate.raw(100000 + random.nextInt(999900000)),
                  discountBp: random.nextInt(3) == 0 ? 0 : random.nextInt(3000),
                  unitCost: Rate.raw(random.nextInt(50000000)),
                  thirdSchedule: random.nextInt(5) == 0,
                );
              }(),
          ];
          final gross = Money.sum([
            for (final l in lines) l.rate.amountFor(l.qty),
          ]);
          final sale = const SaleCalculator(taxEngine: PakistanTaxEngine())
              .calculate(
                SaleDraft(
                  roundToRupee: false,
                  billDiscount: Money.paisa(
                    random.nextInt(4) == 0
                        ? 0
                        : random.nextInt(gross.inPaisa ~/ 5),
                  ),
                  lines: lines,
                ),
                context,
              );

          for (final calculated in sale.lines) {
            var line = _soldFrom(calculated);
            var refund = Money.zero;
            var discount = Money.zero;
            var salesTax = Money.zero;
            var furtherTax = Money.zero;
            var cost = Money.zero;
            var gross = Money.zero;
            var visits = 0;
            while (line.returnable.isPositive) {
              // A tenth of a unit at the least, each time and left over:
              // below a few paisa of goods the taxes give way to the refund
              // (see the test that says so), and a counter steps in units.
              final left = line.returnable.inThousandths;
              final take = left < 200 || random.nextInt(4) == 0
                  ? left
                  : 100 + random.nextInt(left - 199);
              final posting = giveBack(line, Qty.raw(take));
              final share = line.shareOf(Qty.raw(take));
              expect(posting.document.total, share.refund);
              for (final m in [
                share.refund,
                share.discount,
                share.taxable,
                share.salesTax,
                share.furtherTax,
                share.cost,
                share.gross,
              ]) {
                expect(m.isNegative, isFalse, reason: 'run $run');
              }
              refund += share.refund;
              discount += share.discount;
              salesTax += share.salesTax;
              furtherTax += share.furtherTax;
              cost += share.cost;
              gross += share.gross;
              expect(
                refund <= calculated.lineTotal,
                isTrue,
                reason: 'run $run gave back more than was charged on the way',
              );
              line = _after(line, share);
              visits++;
            }
            expect(visits, greaterThan(0));
            expect(refund, calculated.lineTotal, reason: 'run $run refund');
            expect(discount, calculated.totalDiscount, reason: 'run $run');
            expect(salesTax + furtherTax, calculated.tax, reason: 'run $run');
            expect(cost, calculated.cost, reason: 'run $run cost');
            expect(gross, calculated.gross, reason: 'run $run gross');
            expect(line.returnableBase, Qty.zero);
          }
        }
      },
    );

    test('a crore line over a thousand maunds does not wrap', () {
      expect(
        returnedShare(
          const Money.paisa(1000000000000),
          before: 0,
          taking: 333333333,
          outOf: 1000000000,
        ),
        const Money.paisa(333333333000),
      );
    });

    test('a return worth less than a paisa never posts a negative', () {
      // Built by hand so the taxes round up past the refund; a real line
      // needs a return worth under three paisa to get here.
      final line = SoldLine(
        documentLineId: 'L1',
        itemId: 'ITEM-1',
        itemName: 'Supari',
        unitId: 'U-G',
        unitCode: 'g',
        soldQty: Qty.raw(2),
        alreadyReturned: Qty.zero,
        rate: Rate.zero,
        charged: const Money.paisa(2),
        salesTax: const Money.paisa(1),
        furtherTax: const Money.paisa(1),
        cost: Money.zero,
      );
      final posting = giveBack(line, Qty.raw(1));
      expect(posting.lines.single.taxable.isNegative, isFalse);
      expect(posting.journal.totalDebit, posting.journal.totalCredit);
    });
  });

  group('the entry mirrors the sale', () {
    test('Sales Returns is debited gross and the discount comes off Discount '
        'Given', () {
      final line = _sold(
        _line(qty: Qty.units(10), rate: Rate.rupees(100), discountBp: 1000),
      );
      final posting = giveBack(line, Qty.units(10));

      expect(posting.journal.lines.first.accountSystemKey, 'sales_returns');
      expect(on(posting, 'sales_returns')!.debit, const Money.rupees(1000));
      expect(on(posting, 'discount_given')!.credit, const Money.rupees(100));
      expect(
        on(posting, 'accounts_receivable')!.credit,
        const Money.rupees(900),
      );
      expect(posting.document.subtotal, const Money.rupees(1000));
      expect(posting.document.lineDiscount, const Money.rupees(100));
      expect(posting.document.total, const Money.rupees(900));
      expect(posting.lines.single.discount, const Money.rupees(100));
      expect(posting.lines.single.gross, const Money.rupees(1000));
    });

    test('the tax comes back at the rate it was charged at', () {
      final sale = const SaleCalculator(taxEngine: PakistanTaxEngine())
          .calculate(
            SaleDraft(
              lines: [
                _line(
                  qty: Qty.units(2),
                  baseQty: Qty.units(80),
                  rate: Rate.rupees(5000),
                  discountBp: 500,
                  unitCode: 'maund',
                ),
              ],
            ),
            const TaxContext(
              isSellerRegistered: true,
              buyerIsRegistered: false,
              buyerIsOnAtl: null,
              province: 'Punjab',
              pricesIncludeTax: false,
              ruleVersion: 'pk-2026-27-v1',
              hasNamedBuyer: true,
            ),
          );
      final line = _soldFrom(sale.lines.single);
      final posting = giveBack(line, Qty.parse('0.5'));

      final taxes = posting.lines.single.taxes;
      expect(taxes.map((t) => (t.code, t.rateBp)), [
        ('ST_RETURN', 1800),
        ('FURTHER_RETURN', 400),
      ]);
      expect(posting.document.total, const Money.paisa(289750));
      expect(on(posting, 'output_tax')!.debit, const Money.paisa(42750));
      expect(on(posting, 'further_tax_payable')!.debit, const Money.rupees(95));
      expect(on(posting, 'discount_given')!.credit, const Money.rupees(125));
      expect(on(posting, 'sales_returns')!.debit, const Money.rupees(2500));
    });

    test('a loose line still comes back as money only', () {
      final line = SoldLine(
        documentLineId: 'L2',
        itemId: null,
        itemName: 'Pyaz',
        unitId: '',
        unitCode: 'kg',
        soldQty: Qty.parse('2.5'),
        alreadyReturned: Qty.zero,
        rate: Rate.rupees(120),
        charged: const Money.rupees(270),
        discount: const Money.rupees(30),
        cost: Money.zero,
      );
      final posting = giveBack(line, Qty.one, partyId: null);
      expect(posting.stockMovements, isEmpty);
      expect(posting.document.total, const Money.rupees(108));
      expect(posting.journal.totalDebit, posting.journal.totalCredit);
    });
  });

  group('a delivery sent back', () {
    test('goes back in maunds, at the maund it was billed at', () {
      const line = BoughtLine(
        documentLineId: 'D1',
        itemId: 'ITEM-ATTA',
        itemName: 'Atta',
        unitId: 'U-MAUND',
        unitCode: 'maund',
        qty: Qty.raw(2000),
        rate: Rate.rupees(4800),
        boughtQty: Qty.raw(80000),
        alreadyReturned: Qty.zero,
        goodsValue: Money.rupees(9600),
        landedCost: Money.rupees(9600),
      );
      expect(line.returnable, Qty.units(2), reason: 'offered as 80 maund');

      final posting = const PurchaseReturnBuilder().build(
        actor: actor,
        draft: const PurchaseReturnDraft(
          originalDocumentId: 'PB-1',
          reason: 'Geeli bori',
          lines: [ReturnLineDraft(documentLineId: 'D1', qty: Qty.raw(1000))],
        ),
        boughtLines: [line],
        originalDocNo: 'PUR-0001',
        partyId: 'MILL',
        originalOutstanding: const Money.rupees(9600),
        positions: {
          'ITEM-ATTA': CostPosition.onShelf(
            qty: Qty.units(80),
            avg: Rate.rupees(120),
          ),
        },
        returnNumber: number,
        journalNumber: journal,
      );

      expect(posting.document.total, const Money.rupees(4800));
      expect(posting.lines.single.qty, Qty.one);
      expect(posting.lines.single.baseQty, Qty.units(40));
      expect(posting.lines.single.rate, Rate.rupees(4800));
      expect(posting.stockMovements.single.qtyDelta, Qty.units(-40));
    });

    test('part returns are credited exactly what the line was billed', () {
      var line = const BoughtLine(
        documentLineId: 'D1',
        itemId: 'ITEM-1',
        itemName: 'Ghee',
        unitId: 'U-PCS',
        unitCode: 'pcs',
        boughtQty: Qty.raw(3000),
        alreadyReturned: Qty.zero,
        goodsValue: Money.paisa(10000),
        landedCost: Money.paisa(10001),
      );
      var credit = Money.zero;
      var landed = Money.zero;
      for (var i = 0; i < 3; i++) {
        final share = line.shareOf(Qty.one);
        credit += share.credit;
        landed += share.landed;
        line = BoughtLine(
          documentLineId: line.documentLineId,
          itemId: line.itemId,
          itemName: line.itemName,
          unitId: line.unitId,
          unitCode: line.unitCode,
          boughtQty: line.boughtQty,
          alreadyReturned: line.alreadyReturned + Qty.one,
          goodsValue: line.goodsValue,
          landedCost: line.landedCost,
        );
      }
      expect(credit, const Money.paisa(10000));
      expect(landed, const Money.paisa(10001));
    });
  });
}

const _untaxed = TaxContext(
  isSellerRegistered: false,
  buyerIsRegistered: false,
  buyerIsOnAtl: null,
  province: 'Punjab',
  pricesIncludeTax: false,
  ruleVersion: 'none',
);

SaleLineDraft _line({
  required Qty qty,
  required Rate rate,
  Qty? baseQty,
  int discountBp = 0,
  String unitCode = 'pcs',
  String id = 'ITEM-1',
  Rate unitCost = Rate.zero,
  bool thirdSchedule = false,
}) => SaleLineDraft(
  itemId: id,
  itemName: 'Item $id',
  qty: qty,
  baseQty: baseQty ?? qty,
  unitId: 'U-$unitCode',
  unitCode: unitCode,
  rate: rate,
  discountBp: discountBp,
  unitCost: unitCost,
  isThirdSchedule: thirdSchedule,
);

/// A line priced on its own, untaxed, as the bill stored it.
SoldLine _sold(SaleLineDraft draft) => _soldFrom(
  const SaleCalculator()
      .calculate(SaleDraft(lines: [draft]), _untaxed)
      .lines
      .single,
);

/// What the database read gives a return, from what the sale stored.
SoldLine _soldFrom(CalculatedLine l) => SoldLine(
  documentLineId: 'L${l.lineNo}',
  itemId: l.draft.itemId,
  itemName: l.draft.itemName,
  unitId: l.draft.unitId ?? '',
  unitCode: l.draft.unitCode,
  qty: l.draft.qty,
  soldQty: l.draft.baseQty,
  alreadyReturned: Qty.zero,
  rate: l.draft.rate,
  charged: l.lineTotal,
  discount: l.totalDiscount,
  cost: l.cost,
  salesTax: Money.sum([
    for (final t in l.taxes)
      if (t.kind != TaxKind.furtherTax) t.amount,
  ]),
  salesTaxBp: l.taxes
      .where((t) => t.kind == TaxKind.salesTax)
      .fold(0, (bp, t) => max(bp, t.rateBp)),
  furtherTax: Money.sum([
    for (final t in l.taxes)
      if (t.kind == TaxKind.furtherTax) t.amount,
  ]),
  furtherTaxBp: l.taxes
      .where((t) => t.kind == TaxKind.furtherTax)
      .fold(0, (bp, t) => max(bp, t.rateBp)),
  taxInclusive: l.taxes.any((t) => t.kind == TaxKind.salesTax && t.isInclusive),
);

/// The same line after [share] came back, as the next visit reads it.
SoldLine _after(SoldLine l, ReturnShare share) => SoldLine(
  documentLineId: l.documentLineId,
  itemId: l.itemId,
  itemName: l.itemName,
  unitId: l.unitId,
  unitCode: l.unitCode,
  qty: l.qty,
  soldQty: l.soldQty,
  alreadyReturned: l.alreadyReturned + share.baseQty,
  rate: l.rate,
  charged: l.charged,
  discount: l.discount,
  cost: l.cost,
  salesTax: l.salesTax,
  salesTaxBp: l.salesTaxBp,
  furtherTax: l.furtherTax,
  furtherTaxBp: l.furtherTaxBp,
  taxInclusive: l.taxInclusive,
  roundingMode: l.roundingMode,
);
