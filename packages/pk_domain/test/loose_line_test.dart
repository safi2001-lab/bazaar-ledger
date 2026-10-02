import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A line with no item behind it (M37), and an earlier price carried into
/// another unit, checked without a database.
///
/// "Khula maal": a kilo of onions out of the sack, sold by what the cashier
/// calls it and what it comes to. Its money is a sale like any other; it
/// moves no stock and carries no cost, because there is no shelf it left
/// and no cost anybody knows.
void main() {
  const calculator = SaleCalculator();
  const untaxed = TaxContext(
    isSellerRegistered: false,
    buyerIsRegistered: false,
    buyerIsOnAtl: null,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'untaxed-v1',
  );
  final actor = ActorContext(
    firmId: 'F1',
    userId: 'U1',
    deviceId: 'D1',
    startedAtUtc: DateTime.utc(2026, 10, 2, 9, 15),
  );
  const number = AllocatedNumber(
    formatted: 'INV-2627-0001',
    series: 'INV',
    sequence: 1,
  );
  const journal = AllocatedNumber(
    formatted: 'JV-2627-00001',
    series: 'JV',
    sequence: 1,
  );

  SaleLineDraft onions({
    Rate unitCost = Rate.zero,
    String name = 'Pyaz',
    String? lotId,
  }) => SaleLineDraft(
    itemId: null,
    itemName: name,
    qty: Qty.parse('2.500'),
    baseQty: Qty.parse('2.500'),
    unitCode: 'kg',
    rate: Rate.rupees(120),
    unitCost: unitCost,
    lotId: lotId,
    tracksStock: false,
  );

  final oil = SaleLineDraft(
    itemId: 'ITEM-OIL',
    itemName: 'Cooking Oil 5L',
    qty: Qty.one,
    baseQty: Qty.one,
    unitId: 'U-PCS',
    unitCode: 'pcs',
    rate: Rate.rupees(2500),
    unitCost: Rate.rupees(2100),
  );

  group('loose lines', () {
    test('its money is a sale, it moves no stock, and the entry balances', () {
      final draft = SaleDraft(
        lines: [oil, onions()],
        tenders: const [
          TenderDraft(
            paymentAccountId: 'PA-CASH',
            mode: 'cash',
            amount: Money.rupees(2800),
          ),
        ],
      );
      final calculated = calculator.calculate(draft, untaxed);
      final posting = const SalePostingBuilder().build(
        actor: actor,
        draft: draft,
        calculated: calculated,
        invoiceNumber: number,
        journalNumber: journal,
        paymentNumbers: const [
          AllocatedNumber(formatted: 'RCV-1', series: 'RCV', sequence: 1),
        ],
        ledgerAccountByPaymentAccount: const {'PA-CASH': 'ACC-CASH'},
      );

      expect(calculated.total, const Money.rupees(2800));
      // The loose line is written with no item and no cost.
      final loose = posting.lines.firstWhere((l) => l.itemId == null);
      expect(loose.itemNameSnapshot, 'Pyaz');
      expect(loose.lineTotal, const Money.rupees(300));
      expect(loose.cost, Money.zero);
      // Only the oil left a shelf.
      expect(posting.stockMovements.map((m) => m.itemId), ['ITEM-OIL']);

      Money sideOf(String key, {bool credit = false}) => Money.sum([
        for (final l in posting.journal.lines)
          if (l.accountSystemKey == key) credit ? l.credit : l.debit,
      ]);
      expect(sideOf('sales', credit: true), const Money.rupees(2800));
      // Cost is the oil's alone: nothing is known of the onions'.
      expect(sideOf('cogs'), const Money.rupees(2100));
      expect(sideOf('inventory', credit: true), const Money.rupees(2100));
      expect(posting.journal.totalDebit, posting.journal.totalCredit);
      expect(posting.auditSummary, contains('(1 loose)'));
    });

    test('it carries no cost, no batch, and never a blank name', () {
      SaleDraft one(SaleLineDraft line) => SaleDraft(lines: [line]);
      expect(
        () => calculator.calculate(
          one(onions(unitCost: Rate.rupees(90))),
          untaxed,
        ),
        throwsArgumentError,
        reason:
            'a cost with no stock leaving would split the inventory '
            'account from the stock ledger',
      );
      expect(
        () => calculator.calculate(one(onions(lotId: 'LOT-1')), untaxed),
        throwsArgumentError,
      );
      expect(
        () => calculator.calculate(one(onions(name: '  ')), untaxed),
        throwsArgumentError,
      );
    });

    test(
      'it is refused on a quotation, a challan and a bill from a challan',
      () {
        final draft = SaleDraft(lines: [oil, onions()], partyId: 'P1');
        final calculated = calculator.calculate(draft, untaxed);
        expect(
          () => const QuotationBuilder().build(
            actor: actor,
            draft: draft,
            calculated: calculated,
            number: number,
          ),
          throwsA(isA<QuotationRefused>()),
        );
        expect(
          () => const DeliveryChallanBuilder().build(
            actor: actor,
            draft: draft,
            calculated: calculated,
            number: number,
            journalNumber: journal,
          ),
          throwsA(isA<ChallanRefused>()),
        );
        final sent = ChallanGoods(
          challanId: 'CH-1',
          docNo: 'DC-0001',
          partyId: 'P1',
          byItem: {'ITEM-OIL': (qty: Qty.one, cost: const Money.rupees(2100))},
        );
        expect(
          () => sent.costOfLines(calculated.lines),
          throwsA(isA<ChallanRefused>()),
          reason: 'the onions did not go on the challan',
        );
      },
    );

    test('it comes back as money only', () {
      final posting = const ReturnBuilder().build(
        actor: actor,
        draft: const ReturnDraft(
          originalDocumentId: 'DOC-1',
          lines: [ReturnLineDraft(documentLineId: 'L2', qty: Qty.one)],
          reason: 'Kharab thay',
          refundNow: Money.rupees(120),
          paymentAccountId: 'PA-CASH',
        ),
        soldLines: [
          SoldLine(
            documentLineId: 'L2',
            itemId: null,
            itemName: 'Pyaz',
            unitId: '',
            unitCode: 'kg',
            soldQty: Qty.parse('2.500'),
            alreadyReturned: Qty.zero,
            rate: Rate.rupees(120),
            cost: Money.zero,
          ),
        ],
        originalDocNo: 'INV-2627-0001',
        partyId: null,
        originalOutstanding: Money.zero,
        returnNumber: const AllocatedNumber(
          formatted: 'SR-0001',
          series: 'SR',
          sequence: 1,
        ),
        journalNumber: journal,
        refundLedgerAccountId: 'ACC-CASH',
      );
      expect(posting.stockMovements, isEmpty, reason: 'no shelf to go back to');
      expect(posting.lines.single.itemId, isNull);
      expect(posting.refund, const Money.rupees(120));
      expect(
        posting.journal.lines.map((l) => l.accountSystemKey),
        isNot(anyOf(contains('inventory'), contains('cogs'))),
      );
      expect(posting.journal.totalDebit, posting.journal.totalCredit);
    });
  });

  group('past deals', () {
    // A bori of flour is 50 kg here, and a dozen is twelve pieces.
    final units = UnitConverter(const [
      UnitEdge(
        fromUnitId: 'U-BORI',
        toUnitId: 'U-KG',
        factorThousandths: 50000,
        itemId: 'ITEM-ATTA',
      ),
    ]);

    PastDeal deal({
      String? unitId,
      String unitCode = 'bori',
      int rupees = 5000,
    }) => PastDeal(
      documentId: 'DOC-1',
      docNo: 'INV-2627-0007',
      dateLocal: '2026-09-12',
      qty: Qty.units(2),
      unitId: unitId,
      unitCode: unitCode,
      rate: Rate.rupees(rupees),
    );

    test('a price per bori is carried into kilos, exactly or not at all', () {
      expect(
        deal(
          unitId: 'U-BORI',
        ).rateIn('U-KG', itemId: 'ITEM-ATTA', units: units),
        Rate.rupees(100),
        reason: 'five thousand a bori is a hundred a kilo',
      );
      expect(
        deal(
          unitId: 'U-BORI',
          rupees: 5001,
        ).rateIn('U-KG', itemId: 'ITEM-ATTA', units: units),
        Rate.raw(10002000),
        reason: 'a hundred rupees and two paisa a kilo is still exact',
      );
      expect(
        deal(
          unitId: 'U-BORI',
        ).rateIn('U-PCS', itemId: 'ITEM-ATTA', units: units),
        isNull,
        reason: 'flour is not sold by the piece',
      );
    });

    test(
      "a deal in the line's own unit is its price; one with none is not",
      () {
        expect(
          deal(unitId: 'U-KG').rateIn('U-KG', itemId: 'ITEM-ATTA'),
          Rate.rupees(5000),
        );
        expect(
          deal().rateIn('U-KG', itemId: 'ITEM-ATTA', units: units),
          isNull,
          reason:
              'an old line that named no unit cannot be said to be per kilo',
        );
      },
    );
  });
}
