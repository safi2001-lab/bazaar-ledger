import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Pakistan's rules at the counter (M59), as pure arithmetic: the printed
/// price on Third Schedule goods, the province's tax on services at the
/// rate of how the bill is paid, the buyer's name on a big bill, and FBR's
/// offline mode.
const _calculator = SaleCalculator(taxEngine: PakistanTaxEngine());

const _pra = ServiceTaxSetting(
  authority: ServiceTaxAuthority.pra,
  standardBp: 1600,
  digitalBp: 800,
);

TaxContext _ctx({
  bool registered = true,
  bool inclusive = false,
  ServiceTaxSetting? serviceTax,
}) => TaxContext(
  isSellerRegistered: registered,
  buyerIsRegistered: false,
  buyerIsOnAtl: null,
  province: 'punjab',
  pricesIncludeTax: inclusive,
  ruleVersion: 'pk-2026-27-v1',
  serviceTax: serviceTax,
);

SaleLineDraft _pack({
  required int rupees,
  int? mrp,
  int qty = 1,
  int baseQty = 1,
  String unit = 'pcs',
}) => SaleLineDraft(
  itemId: 'biscuits',
  itemName: 'Biscuits',
  qty: Qty.units(qty),
  baseQty: Qty.units(baseQty),
  unitCode: unit,
  rate: Rate.rupees(rupees),
  mrp: mrp == null ? null : Money.rupees(mrp),
  isThirdSchedule: true,
);

SaleLineDraft _service(Money value, {String id = 'haircut'}) => SaleLineDraft(
  itemId: id,
  itemName: 'Haircut',
  qty: Qty.one,
  baseQty: Qty.one,
  unitCode: 'pcs',
  rate: Rate.perUnit(value),
  tracksStock: false,
  isService: true,
);

TenderDraft _tender(String mode, Money amount) =>
    TenderDraft(paymentAccountId: mode, mode: mode, amount: amount);

SaleDraft _bill(
  List<SaleLineDraft> lines, {
  List<TenderDraft> tenders = const [],
}) => SaleDraft(lines: lines, tenders: tenders, roundToRupee: false);

Money _taxOf(CalculatedSale sale, String code) => Money.sum([
  for (final l in sale.lines)
    for (final t in l.taxes)
      if (t.code == code) t.amount,
]);

void main() {
  group('third schedule', () {
    test('a pack sold at its MRP carries MRP x 18/118, as M12 did', () {
      final sale = _calculator.calculate(
        _bill([_pack(rupees: 118, mrp: 118)]),
        _ctx(),
      );
      expect(sale.tax, const Money.rupees(18));
      expect(sale.total, const Money.rupees(118));
      expect(sale.lines.single.taxes.single.code, 'ST_3RD_18');
    });

    test(
      'a pack sold below its MRP still carries the tax on its printed price',
      () {
        // Rs 118 printed, Rs 100 charged: the Rs 18 printed on the pack is
        // still the government's, and the shop's value is what is left.
        final sale = _calculator.calculate(
          _bill([_pack(rupees: 100, mrp: 118)]),
          _ctx(),
        );
        expect(sale.tax, const Money.rupees(18));
        expect(sale.taxable, const Money.rupees(82));
        expect(sale.total, const Money.rupees(100));
      },
    );

    test('a carton of 24 is taxed on 24 printed prices', () {
      // A carton of 24 packs at Rs 50 printed, sold as one carton for
      // Rs 1,150: taxed on Rs 1,200 of printed price, Rs 183.05.
      final sale = _calculator.calculate(
        _bill([_pack(rupees: 1150, mrp: 50, qty: 1, baseQty: 24, unit: 'ctn')]),
        _ctx(),
      );
      expect(sale.tax, const Money.rupees(183, 5));
      expect(sale.total, const Money.rupees(1150));
    });

    test(
      'selling above the MRP is flagged, and the tax is never less than inside what was charged',
      () {
        expect(
          sellsAboveMrp(
            mrp: const Money.rupees(120),
            baseQty: Qty.one,
            lineValue: const Money.rupees(130),
          ),
          isTrue,
        );
        expect(
          sellsAboveMrp(
            mrp: const Money.rupees(120),
            baseQty: Qty.one,
            lineValue: const Money.rupees(120),
          ),
          isFalse,
          reason: 'at the printed price is not above it',
        );
        expect(
          sellsAboveMrp(
            mrp: const Money.rupees(50),
            baseQty: Qty.units(24),
            lineValue: const Money.rupees(1150),
          ),
          isFalse,
          reason: 'a carton of 24 is weighed against 24 printed prices',
        );
        expect(
          sellsAboveMrp(mrp: null, baseQty: Qty.one, lineValue: Money.zero),
          isFalse,
          reason: 'an item with no MRP is never above it',
        );
        final sale = _calculator.calculate(
          _bill([_pack(rupees: 130, mrp: 120)]),
          _ctx(),
        );
        // 130 x 18/118 = 19.83, more than the 18.31 inside the printed price.
        expect(sale.tax, const Money.rupees(19, 83));
        expect(sale.total, const Money.rupees(130));
      },
    );

    test(
      'with no MRP the tax is taken out of the price charged, as before',
      () {
        final sale = _calculator.calculate(_bill([_pack(rupees: 236)]), _ctx());
        expect(sale.tax, const Money.rupees(36));
      },
    );

    test('the tax is never more than the line itself', () {
      final sale = _calculator.calculate(
        _bill([_pack(rupees: 10, mrp: 1180)]),
        _ctx(),
      );
      expect(sale.tax, const Money.rupees(10));
      expect(sale.taxable, Money.zero);
      expect(sale.total, const Money.rupees(10));
    });

    test('an unregistered shop charges none, MRP or not', () {
      final sale = _calculator.calculate(
        _bill([_pack(rupees: 100, mrp: 118)]),
        _ctx(registered: false),
      );
      expect(sale.tax, Money.zero);
    });
  });

  group('provincial tax on services', () {
    test('PRA charges 16% on a service paid in cash', () {
      final sale = _calculator.calculate(
        _bill(
          [_service(const Money.rupees(1000))],
          tenders: [_tender('cash', const Money.rupees(1160))],
        ),
        _ctx(serviceTax: _pra),
      );
      final tax = sale.lines.single.taxes.single;
      expect(tax.kind, TaxKind.provincialSt);
      expect(tax.code, 'PRA_STD');
      expect(tax.rateBp, 1600);
      expect(tax.amount, const Money.rupees(160));
      expect(sale.total, const Money.rupees(1160));
      expect(sale.balance, Money.zero);
    });

    test('PRA charges 8% on a service paid by card', () {
      final sale = _calculator.calculate(
        _bill(
          [_service(const Money.rupees(1000))],
          tenders: [_tender('card', const Money.rupees(1080))],
        ),
        _ctx(serviceTax: _pra),
      );
      final tax = sale.lines.single.taxes.single;
      expect(tax.code, 'PRA_CARD');
      expect(tax.rateBp, 800);
      expect(tax.amount, const Money.rupees(80));
      expect(sale.total, const Money.rupees(1080));
      expect(sale.balance, Money.zero);
      expect(serviceTaxLabel(tax.code, tax.rateBp), 'PRA 8% (card)');
      expect(serviceTaxLabel('PRA_STD', 1600), 'PRA 16%');
    });

    test('the price before the money is taken follows the mode picked', () {
      final draft = _bill([_service(const Money.rupees(1000))]);
      final ctx = _ctx(serviceTax: _pra);
      Money due(String? mode) =>
          _calculator.settledWholly(draft, ctx, mode).total;
      expect(due(null), const Money.rupees(1160));
      expect(due('cash'), const Money.rupees(1160));
      expect(due('card'), const Money.rupees(1080));
      expect(due('jazzcash'), const Money.rupees(1080));
      expect(due('easypaisa'), const Money.rupees(1080));
      expect(due('raast'), const Money.rupees(1080));
      expect(due('bank_transfer'), const Money.rupees(1160));
      expect(due('cheque'), const Money.rupees(1160));
      // And the bill with no tender at all is the cash price.
      expect(_calculator.calculate(draft, ctx).total, const Money.rupees(1160));
    });

    test(
      'a split tender taxes each part at its rate, pro-rata, and the card pays exactly its slice',
      () {
        // Rs 500 on the card against a bill that would be Rs 1,080 all on
        // the card: the card pays 500/1080 of the haircut at 8%, the cash the
        // rest at 16%.
        final sale = _calculator.calculate(
          _bill(
            [_service(const Money.rupees(1000))],
            tenders: [
              _tender('card', const Money.rupees(500)),
              _tender('cash', const Money.rupees(623)),
            ],
          ),
          _ctx(serviceTax: _pra),
        );
        final taxes = sale.lines.single.taxes;
        final card = taxes.singleWhere((t) => t.code == 'PRA_CARD');
        final cash = taxes.singleWhere((t) => t.code == 'PRA_STD');
        expect(card.base, const Money.rupees(462, 96));
        expect(card.amount, const Money.rupees(37, 4));
        expect(card.base + card.amount, const Money.rupees(500));
        expect(cash.base, const Money.rupees(537, 4));
        expect(cash.amount, const Money.rupees(85, 93));
        expect(card.base + cash.base, const Money.rupees(1000));
        expect(sale.tax, card.amount + cash.amount);
        expect(sale.total, const Money.rupees(1122, 97));
        expect(sale.paid, const Money.rupees(1122, 97));
        expect(sale.changeDue, const Money.paisa(3));
        expect(sale.balance, Money.zero);
      },
    );

    test('any split of any bill adds up to the paisa', () {
      final random = Random(59);
      final ctx = _ctx(serviceTax: _pra);
      for (var round = 0; round < 400; round++) {
        final services = [
          for (var i = 0; i < 1 + random.nextInt(3); i++)
            _service(
              Money.paisa(100 + random.nextInt(5000000)),
              id: 'service-$i',
            ),
        ];
        final goods = [
          if (random.nextBool())
            SaleLineDraft(
              itemId: 'ghee',
              itemName: 'Ghee',
              qty: Qty.units(1 + random.nextInt(5)),
              baseQty: Qty.one,
              unitCode: 'pcs',
              rate: Rate.rupees(1 + random.nextInt(3000)),
            ),
        ];
        final draft = _bill([...services, ...goods]);
        final whole = _calculator.settledWholly(draft, ctx, 'card').total;
        final card = Money.paisa(1 + random.nextInt(whole.inPaisa));
        final sale = _calculator.calculate(
          _bill(
            [...services, ...goods],
            tenders: [_tender('card', card), _tender('cash', whole * 2)],
          ),
          ctx,
        );
        final reason = 'round $round, card $card of $whole';
        // Every tax row is in the bill's tax, and nothing else is.
        expect(
          sale.tax + sale.furtherTax,
          Money.sum([
            for (final l in sale.lines)
              for (final t in l.taxes) t.amount,
          ]),
          reason: reason,
        );
        // Each service's two parts add back to its value exactly.
        for (final l in sale.lines.where((l) => l.draft.isService)) {
          expect(
            Money.sum([for (final t in l.taxes) t.base]),
            l.taxable,
            reason: reason,
          );
          expect(l.lineTotal, l.taxable + l.tax, reason: reason);
        }
        // The lines are the bill, and the money taken is the bill.
        expect(
          sale.total,
          Money.sum([for (final l in sale.lines) l.lineTotal]) + sale.roundOff,
          reason: reason,
        );
        expect(sale.paid + sale.balance, sale.total, reason: reason);
        expect(sale.balance, Money.zero, reason: reason);
        // The card never pays more than the bill, and the bill is never
        // dearer than all of it in cash nor cheaper than all on the card —
        // give or take the paisa each part of each service rounds on its
        // own.
        final slack = services.length;
        final allCash = _calculator.calculate(draft, ctx).total;
        expect(card <= sale.total, isTrue, reason: reason);
        expect(
          sale.total.inPaisa <= allCash.inPaisa + slack,
          isTrue,
          reason: reason,
        );
        expect(
          sale.total.inPaisa >= whole.inPaisa - slack,
          isTrue,
          reason: reason,
        );
      }
    });

    test('SRB charges 15% in cash and 8% by card', () {
      const srb = ServiceTaxSetting(
        authority: ServiceTaxAuthority.srb,
        standardBp: 1500,
        digitalBp: 800,
      );
      expect(ServiceTaxSetting.publishedFor(ServiceTaxAuthority.srb), srb);
      expect(ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra), _pra);
      final draft = _bill([_service(const Money.rupees(2000))]);
      final ctx = _ctx(serviceTax: srb);
      expect(
        _calculator.settledWholly(draft, ctx, 'cash').total,
        const Money.rupees(2300),
      );
      final card = _calculator.settledWholly(draft, ctx, 'card');
      expect(card.total, const Money.rupees(2160));
      expect(card.lines.single.taxes.single.code, 'SRB_CARD');
    });

    test(
      'goods on the same bill keep the federal tax, and a service never carries it',
      () {
        final sale = _calculator.calculate(
          _bill(
            [
              _service(const Money.rupees(1000)),
              SaleLineDraft(
                itemId: 'gel',
                itemName: 'Hair gel',
                qty: Qty.one,
                baseQty: Qty.one,
                unitCode: 'pcs',
                rate: Rate.rupees(500),
              ),
            ],
            tenders: [_tender('card', const Money.rupees(1670))],
          ),
          _ctx(serviceTax: _pra),
        );
        expect(_taxOf(sale, 'ST_STD_18'), const Money.rupees(90));
        expect(_taxOf(sale, 'PRA_CARD'), const Money.rupees(80));
        expect(
          sale.lines.first.taxes.every((t) => t.kind == TaxKind.provincialSt),
          isTrue,
        );
        expect(sale.total, const Money.rupees(1670));
      },
    );

    test('a shop with no authority set charges no tax on a service', () {
      final sale = _calculator.calculate(
        _bill([_service(const Money.rupees(1000))]),
        _ctx(),
      );
      expect(sale.tax, Money.zero);
      expect(sale.total, const Money.rupees(1000));
    });

    test(
      'prices that include tax have the provincial tax taken out, at the rate of the mode',
      () {
        final draft = _bill([_service(const Money.rupees(1160))]);
        final ctx = _ctx(inclusive: true, serviceTax: _pra);
        final cash = _calculator.settledWholly(draft, ctx, 'cash');
        expect(cash.total, const Money.rupees(1160));
        expect(cash.tax, const Money.rupees(160));
        expect(cash.taxable, const Money.rupees(1000));
        final card = _calculator.settledWholly(draft, ctx, 'card');
        expect(card.total, const Money.rupees(1160));
        // 1160 x 8/108 = 85.93.
        expect(card.tax, const Money.rupees(85, 93));
        expect(card.inclusiveTax, const Money.rupees(85, 93));
      },
    );

    test(
      'a card rate set equal to the cash rate never changes with the tender',
      () {
        const flat = ServiceTaxSetting(
          authority: ServiceTaxAuthority.pra,
          standardBp: 1600,
          digitalBp: 1600,
        );
        final sale = _calculator.calculate(
          _bill(
            [_service(const Money.rupees(1000))],
            tenders: [_tender('card', const Money.rupees(1160))],
          ),
          _ctx(serviceTax: flat),
        );
        expect(sale.lines.single.taxes.single.code, 'PRA_STD');
        expect(sale.total, const Money.rupees(1160));
      },
    );

    test('a card cannot pay more than the bill at the card rate', () {
      expect(
        () => _calculator.calculate(
          _bill(
            [_service(const Money.rupees(1000))],
            tenders: [_tender('card', const Money.rupees(1160))],
          ),
          _ctx(serviceTax: _pra),
        ),
        throwsArgumentError,
      );
    });

    test(
      'the setting reads back what was written, and nonsense reads as none',
      () {
        expect(ServiceTaxSetting.decode(_pra.encode()), _pra);
        const kp = ServiceTaxSetting(
          authority: ServiceTaxAuthority.kpra,
          standardBp: 1500,
          digitalBp: 1000,
        );
        expect(ServiceTaxSetting.decode('kpra:1500:1000'), kp);
        expect(
          ServiceTaxSetting.publishedFor(ServiceTaxAuthority.kpra),
          isNull,
        );
        expect(ServiceTaxSetting.publishedFor(ServiceTaxAuthority.bra), isNull);
        for (final raw in [
          null,
          '',
          'none',
          'pra:16:8:1',
          'xyz:1600:800',
          'pra:abc:800',
          'pra:9000:800',
        ]) {
          expect(ServiceTaxSetting.decode(raw), isNull, reason: '$raw');
        }
        expect(percentOfBp(850), '8.5%');
        expect(percentOfBp(1275), '12.75%');
      },
    );
  });

  group('buyer name', () {
    test(
      'a walk-in bill over Rs 100,000 asks for a name; a named one or a smaller one does not',
      () {
        expect(
          buyerNameNeeded(
            total: const Money.rupees(120000),
            partyId: null,
            buyerName: null,
          ),
          isTrue,
        );
        expect(
          buyerNameNeeded(
            total: const Money.rupees(120000),
            partyId: null,
            buyerName: '  ',
          ),
          isTrue,
          reason: 'spaces are not a name',
        );
        expect(
          buyerNameNeeded(
            total: const Money.rupees(120000),
            partyId: null,
            buyerName: 'Imran Ahmed',
          ),
          isFalse,
        );
        expect(
          buyerNameNeeded(
            total: const Money.rupees(120000),
            partyId: 'party-1',
            buyerName: null,
          ),
          isFalse,
          reason: 'a customer in the khata already names the bill',
        );
        expect(
          buyerNameNeeded(
            total: const Money.rupees(100000),
            partyId: null,
            buyerName: null,
          ),
          isFalse,
          reason: 'the rule is over Rs 100,000, not at it',
        );
      },
    );

    test(
      'a CNIC is written with its dashes from thirteen digits, and nothing else is one',
      () {
        expect(tidyCnic('3520212345671'), '35202-1234567-1');
        expect(tidyCnic('35202-1234567-1'), '35202-1234567-1');
        expect(tidyCnic(' 35202 1234567 1 '), '35202-1234567-1');
        expect(tidyCnic('35202-123456-1'), isNull);
        expect(tidyCnic(''), isNull);
        expect(tidyCnic(null), isNull);
      },
    );
  });

  group('offline mode', () {
    test(
      'the connection came back at the first answer after the bill, and the bill is late a day later',
      () {
        final made = DateTime.utc(2026, 10, 3, 5);
        final back = connectionBackFor(
          madeAtUtc: made,
          answeredAtUtc: [
            DateTime.utc(2026, 10, 3, 4),
            null,
            DateTime.utc(2026, 10, 3, 9),
            DateTime.utc(2026, 10, 3, 7),
          ],
        );
        expect(back, DateTime.utc(2026, 10, 3, 7));
        expect(
          connectionBackFor(madeAtUtc: made, answeredAtUtc: const []),
          isNull,
        );
        bool late(String status, Duration after) => offlineOverdue(
          status: status,
          connectionBackAtUtc: back,
          nowUtc: back!.add(after),
        );
        expect(late('pending', const Duration(hours: 23)), isFalse);
        expect(late('pending', const Duration(hours: 24)), isFalse);
        expect(late('pending', const Duration(hours: 24, minutes: 1)), isTrue);
        expect(late('posted', const Duration(days: 3)), isFalse);
        expect(
          offlineOverdue(
            status: 'pending',
            connectionBackAtUtc: null,
            nowUtc: DateTime.utc(2027),
          ),
          isFalse,
          reason: 'while FBR has not been heard from, nothing is late yet',
        );
        expect(offlineInvoiceMark, contains('Issued in offline mode'));
      },
    );
  });
}
