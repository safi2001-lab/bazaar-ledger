import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:bazaar_ledger/features/sales/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A bill rung again without typing it twice (M36).
///
/// "Same as last week" is how a wholesaler's regular customer orders, and a
/// bill cancelled by mistake has to be made again. Both were thirty lines of
/// searching while the customer waited. Now a bill's goods and customer go
/// onto the counter as a new bill — from the bill, from its row in the
/// sales list, or from the counter once the customer is named — at today's
/// prices or the prices billed, as the cashier says. The old bill is never
/// touched.
void main() {
  testWidgets(
    "a bill rung again at today's prices puts its goods and customer on the "
    'counter as a new bill, and leaves the old one as it was',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _soldToRashid(app);

      await _openBill(tester, old);
      await _copyFromMenu(tester);
      await tapButton(tester, 'Aaj ke rate');

      expect(find.text('$old ki naqal counter par hai'), findsOneWidget);
      expect(find.text('Rashid Traders ka bill'), findsOneWidget);
      // Rashid buys wholesale, and wholesale is Rs 2,300 today.
      expect(find.text('× 2,300.00'), findsOneWidget);

      await tapButton(tester, 'Paisay lein');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save karein');

      final bills = await app.rowsOf(
        'SELECT doc_no, status, party_id, total_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice' ORDER BY created_at_utc",
      );
      expect(bills, hasLength(2));
      expect(bills.first['doc_no'], old);
      expect(bills.first['status'], 'posted');
      expect(bills.first['total_paisa'], 480000);
      expect(bills.last['total_paisa'], 460000);
      expect(bills.last['party_id'], bills.first['party_id']);
      expect(await app.countIn('doc_links'), 0);
    },
  );

  testWidgets('at the prices billed, a bill rung again keeps its old price', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final old = await _soldToRashid(app);

    await _openBill(tester, old);
    await _copyFromMenu(tester);
    await tapButton(tester, 'Purane rate');

    expect(find.text('× 2,400.00'), findsOneWidget);
  });

  testWidgets('a cancelled bill can be rung again', (tester) async {
    final app = await Harness.startWithShop(tester);
    final old = await _soldToRashid(app);
    final id = await app.scalar<String>('SELECT id FROM documents');
    await app.services.voidDocument(
      app.services.actorNow(),
      documentId: id!,
      reason: 'Galat entry',
    );

    await _openBill(tester, old);
    expect(find.byTooltip('Bill mansookh'), findsNothing);
    await _copyFromMenu(tester);
    await tapButton(tester, 'Aaj ke rate');

    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(find.text('Rashid Traders ka bill'), findsOneWidget);
  });

  testWidgets('a bill is rung again from its row in the sales list', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final old = await _soldToRashid(app);

    await tester.pumpAndSettle();
    await tapText(tester, 'Farokht');
    await tester.longPress(find.text(old).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Isi tarah ka naya bill');
    await tapButton(tester, 'Aaj ke rate');

    expect(find.text('Naya Bill'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(find.text('Rashid Traders ka bill'), findsOneWidget);
  });

  testWidgets(
    "the counter offers a named customer's last order, and one tap puts it "
    'back',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _soldToRashid(app);

      await tester.pumpAndSettle();
      await tapText(tester, 'Naya Bill');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bill kis ke naam'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Rashid Traders');

      await tapButton(tester, 'Pichhla order dobara ($old)');
      await tapButton(tester, 'Purane rate');

      expect(find.text('Cooking Oil 5L'), findsOneWidget);
      expect(find.text('× 2,400.00'), findsOneWidget);
    },
  );

  testWidgets(
    'khula maal comes back as khula maal, and an item archived since is '
    'left out and said',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _soldToRashid(app, withLoose: true);
      final oil = await app.scalar<String>('SELECT id FROM items');
      await app.services.catalogue.archiveItem(app.services.actorNow(), oil!);

      await _openBill(tester, old);
      await _copyFromMenu(tester);
      await tapButton(tester, 'Aaj ke rate');

      expect(find.text('Pyaz'), findsOneWidget);
      expect(find.text('Khula maal · stock nahi'), findsOneWidget);
      expect(find.text('Cooking Oil 5L'), findsNothing);
      expect(
        find.text('Yeh nahi aayin: Cooking Oil 5L (cheez hata di gayi)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a bill is never rung again over a bill being rung', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final old = await _soldToRashid(app);
    final oil = await app.scalar<String>('SELECT id FROM items');
    final item = await app.services.queries.itemById(
      app.services.identity!.firmId,
      oil!,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(cartProvider.notifier).add(item!);

    await _openBill(tester, old);
    await _copyFromMenu(tester);

    expect(
      find.textContaining('pehle se ek bill chal raha hai'),
      findsOneWidget,
    );
    expect(container.read(cartProvider).lines.single.qty, Qty.one);
  });

  testWidgets('a cancel is given its reason from presets', (tester) async {
    final app = await Harness.startWithShop(tester);
    final old = await _soldToRashid(app);

    await _openBill(tester, old);
    await tester.tap(find.byTooltip('Bill mansookh'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak ne order chhor diya');
    await tapButton(tester, 'Haan, mansookh karein');

    expect(
      await app.scalar<String>('SELECT void_reason FROM documents'),
      'Gahak ne order chhor diya',
    );
  });

  testWidgets(
    "the receipt preview keeps the paper's own size whatever the text size",
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await Harness.startWithShop(tester);
      final old = await _soldToRashid(app);

      await _openBill(tester, old);

      final paper = tester.element(
        find.descendant(
          of: find.byType(PaperPreview),
          matching: find.byType(SelectableText),
        ),
      );
      expect(MediaQuery.textScalerOf(paper), TextScaler.noScaling);
      // And the rest of the screen still follows the phone.
      final title = tester.element(find.text('Bill $old'));
      expect(MediaQuery.textScalerOf(title).scale(10), greaterThan(10));
    },
  );

  group('discounts as billed', () {
    const untaxed = TaxContext(
      isSellerRegistered: false,
      buyerIsRegistered: false,
      buyerIsOnAtl: null,
      province: 'punjab',
      pricesIncludeTax: false,
      ruleVersion: 'test',
    );

    SaleLineDraft line(int rupees, int qty, {int bp = 0, Money? off}) =>
        SaleLineDraft(
          itemId: 'item-$rupees',
          itemName: 'Item $rupees',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
          discountBp: bp,
          explicitDiscount: off,
          tracksStock: false,
        );

    /// The bill as stored, read back as a copy.
    List<BillCopyLine> billed(SaleDraft draft) {
      final sale = const SaleCalculator().calculate(draft, untaxed);
      return [
        for (final l in sale.lines)
          BillCopyLine(
            itemId: l.draft.itemId,
            name: l.draft.itemName,
            qty: l.draft.qty,
            unitCode: l.draft.unitCode,
            rate: l.draft.rate,
            discountBp: l.draft.discountBp,
            discount: l.totalDiscount,
          ),
      ];
    }

    /// Prices [lines] again with what came back, line by line.
    List<Money> again(
      List<SaleLineDraft> lines,
      ({List<CopiedDiscount> lines, Money billDiscount}) back,
    ) {
      final sale = const SaleCalculator().calculate(
        SaleDraft(
          lines: [
            for (var i = 0; i < lines.length; i++)
              line(
                lines[i].rate.inMilliPaisa ~/ 100000,
                lines[i].qty.inThousandths ~/ 1000,
                bp: back.lines[i].discountBp,
                off: back.lines[i].explicitDiscount,
              ),
          ],
          billDiscount: back.billDiscount,
          roundToRupee: false,
        ),
        untaxed,
      );
      return [for (final l in sale.lines) l.totalDiscount];
    }

    test('a percentage on a line and a discount on the bill come back as '
        'they were typed', () {
      final lines = [line(100, 2, bp: 1000), line(300, 1)];
      final draft = SaleDraft(
        lines: lines,
        billDiscount: const Money.rupees(48),
        roundToRupee: false,
      );
      final copy = billed(draft);
      final back = discountsAsBilled(
        copy,
        billDiscount: const Money.rupees(48),
      );
      expect(back.billDiscount, const Money.rupees(48));
      expect(back.lines.first.discountBp, 1000);
      expect(back.lines.last.explicitDiscount, isNull);
      expect(again(lines, back), [for (final l in copy) l.discount]);
    });

    test('rupees typed on a line beside a discount on the bill come back as '
        'exact rupees on each line', () {
      final lines = [line(100, 2, off: const Money.rupees(25)), line(300, 1)];
      final draft = SaleDraft(
        lines: lines,
        billDiscount: const Money.rupees(48),
        roundToRupee: false,
      );
      final copy = billed(draft);
      final back = discountsAsBilled(
        copy,
        billDiscount: const Money.rupees(48),
      );
      expect(back.billDiscount, Money.zero);
      expect(again(lines, back), [for (final l in copy) l.discount]);
      expect(
        Money.sum([for (final l in back.lines) l.explicitDiscount!]),
        const Money.rupees(73),
        reason: 'what came off the bill in all is what comes off the copy',
      );
    });

    test('with no discount on the bill, rupees typed on a line come back as '
        'typed', () {
      final lines = [line(100, 2, off: const Money.rupees(25)), line(300, 1)];
      final copy = billed(SaleDraft(lines: lines, roundToRupee: false));
      final back = discountsAsBilled(copy, billDiscount: Money.zero);
      expect(back.lines.first.explicitDiscount, const Money.rupees(25));
      expect(back.lines.last.explicitDiscount, isNull);
    });
  });

  group('the cart draft', () {
    ItemSummary oil() => ItemSummary(
      id: 'item-oil',
      name: 'Cooking Oil 5L',
      unitId: 'unit-pcs',
      unitCode: 'pcs',
      unitDecimals: 0,
      saleRate: Rate.rupees(2500),
      stockOnHand: Qty.units(20),
      tracksStock: true,
    );

    test('a bill being put right survives the app being killed, the bill it '
        'replaces and the money already taken with it', () {
      final cart = Cart(
        lines: [
          CartLine(item: oil(), qty: Qty.units(2), rate: Rate.rupees(2400)),
        ],
        partyId: 'party-1',
        partyName: 'Rashid Traders',
        replacesId: 'doc-1',
        replacesNo: 'INV-1',
        paidBefore: PaidBefore(
          amount: const Money.rupees(4800),
          mode: 'cheque',
          chequeNo: '000777',
          chequeBank: 'Meezan',
          chequeDateUtcMillis: DateTime.utc(2026, 10, 3).millisecondsSinceEpoch,
        ),
      );
      final back = CartDraft.decode(CartDraft.encode(cart))!;
      expect(back.replacesId, 'doc-1');
      expect(back.replacesNo, 'INV-1');
      expect(back.paidBefore!.amount, const Money.rupees(4800));
      expect(back.paidBefore!.mode, 'cheque');
      expect(back.paidBefore!.chequeNo, '000777');
      expect(back.paidBefore!.chequeBank, 'Meezan');
      expect(
        back.paidBefore!.chequeDateUtcMillis,
        DateTime.utc(2026, 10, 3).millisecondsSinceEpoch,
      );
    });

    test('a draft from the build before it is read as a bill putting '
        'nothing right', () {
      final v4 = CartDraft.encode(
        Cart(
          lines: [CartLine(item: oil(), qty: Qty.one, rate: Rate.rupees(2500))],
        ),
      ).replaceFirst('"v":${CartDraft.version}', '"v":4');
      final back = CartDraft.decode(v4)!;
      expect(back.lines.single.qty, Qty.one);
      expect(back.replacesId, isNull);
      expect(back.paidBefore, isNull);
    });
  });
}

Future<void> _openBill(WidgetTester tester, String docNo) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
  await tester.tap(find.text(docNo).first);
  await tester.pumpAndSettle();
}

Future<void> _copyFromMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Aur'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Isi tarah ka naya bill').last);
  await tester.pumpAndSettle();
}

/// Two tins of oil to Rashid Traders, a wholesale customer, at Rs 2,400 —
/// a price somebody typed — on udhaar; with [withLoose], two kilos of
/// loose onions at Rs 80 too. Returns the bill's number.
Future<String> _soldToRashid(Harness app, {bool withLoose = false}) async {
  final services = app.services;
  final firm = services.identity!.firmId;
  final pcs = (await services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final oil = await services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(2500),
      wholesaleRate: Rate.rupees(2300),
      openingStock: Qty.units(50),
      openingRate: Rate.rupees(2000),
    ),
  );
  final rashid = await services.catalogue.addParty(
    services.actorNow(),
    const PartyDraft(name: 'Rashid Traders', priceTier: PriceTier.wholesale),
  );
  final sale = await services.postSale(
    services.actorNow(),
    SaleDraft(
      partyId: rashid,
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(2),
          baseQty: Qty.units(2),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(2400),
        ),
        if (withLoose)
          SaleLineDraft(
            itemId: null,
            itemName: 'Pyaz',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitCode: '',
            rate: Rate.rupees(80),
            tracksStock: false,
          ),
      ],
    ),
  );
  return sale.docNo;
}
