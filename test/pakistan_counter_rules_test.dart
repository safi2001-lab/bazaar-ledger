import 'package:bazaar_ledger/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// FBR as a stand-in that answers what the test tells it to.
final class _Fbr implements FbrGateway {
  FbrOutcome answer = const FbrTryLater('No signal.');

  @override
  Future<FbrOutcome> post(String payloadJson) async => answer;
}

/// Pakistan's rules at the counter (M59), from the screens: the buyer's
/// name on a big bill, the printed price on Third Schedule goods, the
/// province's tax on a service at the rate of the tender, and FBR's offline
/// mode on Home.
void main() {
  testWidgets(
    'a Rs 120,000 walk-in bill asks for the buyer\'s name, and the name is on the bill',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await app.services.updateFirm({'is_sales_tax_registered': 1});
      _bump(tester);
      await app.seedItem(name: 'Salon chair', rupees: 120000);

      await _ringUp(tester, 'Salon');
      await tapButton(tester, 'Paisay lein');
      // Rs 1,20,000 and 18%: over the line, to nobody.
      expect(find.text('Rs 1,41,600.00'), findsWidgets);
      expect(
        find.text('Khareedar ka naam: Rs 1 lakh se bara bill'),
        findsOneWidget,
      );

      await typeInto(tester, 'Diye gaye', '141600');
      await tapButton(tester, 'Save karein');
      expect(
        find.text(
          'Pehle khareedar ka naam likhein: Rs 1,00,000 se bare bill par FBR ko chahiye.',
        ),
        findsOneWidget,
      );
      expect(
        await app.scalar<int>(
          "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        0,
        reason: 'nothing is written until the bill names its buyer',
      );

      await typeInto(tester, 'Khareedar ka naam', 'Imran Ahmed');
      await typeInto(tester, 'CNIC (agar dein)', '3520212345671');
      await tapButton(tester, 'Save karein');

      final bill = await app.rowsOf(
        'SELECT party_id, party_name_snapshot, party_ntn_snapshot, total_paisa '
        "FROM documents WHERE doc_type = 'sale_invoice'",
      );
      expect(bill.single['party_id'], isNull);
      expect(bill.single['party_name_snapshot'], 'Imran Ahmed');
      expect(bill.single['party_ntn_snapshot'], '35202-1234567-1');
      expect(bill.single['total_paisa'], 14160000);
      // The receipt opens on the bill, made out to them.
      expect(find.textContaining('Imran Ahmed'), findsWidgets);
    },
  );

  testWidgets(
    'a Third Schedule item sold above its printed price is warned of on its line',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final pcs = await _pieces(app);
      for (final (name, price, mrp) in [
        ('Shampoo 400ml', 130, 120),
        ('Sabun', 50, 50),
      ]) {
        await app.services.catalogue.addItem(
          app.services.actorNow(),
          ItemDraft(
            name: name,
            baseUnitId: pcs,
            saleRate: Rate.rupees(price),
            mrp: Money.rupees(mrp),
            isThirdSchedule: true,
            openingStock: Qty.units(20),
          ),
        );
      }

      await _ringUp(tester, 'Shampoo');
      await _ringUp(tester, 'Sabun', newBill: false);
      expect(
        find.text('MRP Rs 120.00 · chhapi qeemat se zyada'),
        findsOneWidget,
      );
      // At its printed price the line just says what the pack says.
      expect(find.text('MRP Rs 50.00'), findsOneWidget);
    },
  );

  testWidgets(
    'the owner marks an item Third Schedule in its editor, and it needs its MRP',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await tester.tap(find.text('Maal').first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Naya maal');
      await typeInto(tester, 'Naam', 'Juice 1L');
      await typeInto(tester, 'Farokht ki qeemat', '118');
      await tester.tap(find.text('Aur tafseel'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Third Schedule (chhapi qeemat par bikta hai)');

      await tapButton(tester, 'Save karein');
      expect(
        find.text('Third Schedule item ki MRP (chhapi qeemat) likhein.'),
        findsOneWidget,
      );
      expect(await app.countIn('items'), 0);

      await typeInto(tester, 'MRP (chhapi qeemat)', '118');
      await tapButton(tester, 'Save karein');
      final row = await app.rowsOf(
        'SELECT is_third_schedule, item_type, mrp_paisa FROM items',
      );
      expect(row.single['is_third_schedule'], 1);
      expect(row.single['item_type'], 'goods');
      expect(row.single['mrp_paisa'], 11800);
    },
  );

  testWidgets(
    'a salon sets PRA in Tax, and the payment sheet charges 16% in cash and 8% by card',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await app.services.catalogue.addItem(
        app.services.actorNow(),
        ItemDraft(
          name: 'Haircut',
          baseUnitId: await _pieces(app),
          saleRate: Rate.rupees(1000),
          tracksStock: false,
          isService: true,
        ),
      );

      await openSettings(tester);
      await tapText(tester, 'Tax');
      await tapText(tester, 'PRA (Punjab)');
      await tapButton(tester, 'Service tax save karein');
      expect(find.text('Service tax save ho gaya'), findsOneWidget);
      // The rates PRA published, filled in for the owner.
      expect(
        await app.services.counterTax.serviceTax(),
        ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _ringUp(tester, 'Haircut');
      expect(find.text('Rs 1,160.00'), findsWidgets);
      await tapButton(tester, 'Paisay lein');
      expect(find.text('PRA 16%'), findsOneWidget);

      await _payBy(tester, 'Card');
      await tester.pumpAndSettle();
      expect(find.text('Rs 1,080.00'), findsWidgets);
      expect(find.text('PRA 8% (card)'), findsOneWidget);
      await tapButton(tester, 'Save karein');

      final bill = await app.rowsOf(
        'SELECT d.total_paisa, d.tax_paisa, t.tax_code, t.rate_bp '
        'FROM documents d JOIN document_line_taxes t ON t.document_id = d.id '
        "WHERE d.doc_type = 'sale_invoice'",
      );
      expect(bill.single['total_paisa'], 108000);
      expect(bill.single['tax_paisa'], 8000);
      expect(bill.single['tax_code'], 'PRA_CARD');
      expect(bill.single['rate_bp'], 800);
      // The receipt says what the tax was, and why it was less.
      expect(find.textContaining('PRA 8% (card)'), findsOneWidget);
    },
  );

  testWidgets(
    'a bill FBR has not taken a day after the connection came back is shown on Home and the FBR screen',
    (tester) async {
      final clock = FixedClock(DateTime.utc(2026, 10, 3, 5));
      final app = await Harness.startWithShop(tester, clock: clock);
      final shop = app.services;
      await shop.updateFirm({'is_sales_tax_registered': 1, 'ntn': '1234567-8'});
      final fbr = _Fbr();
      shop.fbr.gatewayFor = (_) => fbr;
      await shop.fbr.save(const FbrSettings(enabled: true, token: 'pral'));
      final firm = shop.identity!.firmId;
      final oil = await shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: 'Cooking oil 5L',
          baseUnitId: await _pieces(app),
          saleRate: Rate.rupees(2500),
          hsCode: '1512.1900',
          openingStock: Qty.units(10),
        ),
      );
      final cash = (await shop.queries.paymentAccounts(
        firm,
      )).firstWhere((a) => a.modeLabel == 'cash');

      // No signal: the bill goes out marked offline.
      final sale = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: oil,
              itemName: 'Cooking oil 5L',
              hsCode: '1512.1900',
              qty: Qty.units(2),
              baseQty: Qty.units(2),
              unitCode: 'pcs',
              rate: Rate.rupees(2500),
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash.id,
              mode: 'cash',
              amount: const Money.rupees(5900),
            ),
          ],
        ),
      );
      await shop.fbr.afterSale(sale.documentId);
      await shop.fbr.sendPending();
      // A tin comes back; its credit note waits for the bill's FBR number.
      final sold = (await shop.queries.returnableLines(
        firm,
        sale.documentId,
      )).single;
      final back = await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Dabba toota hua',
          refundNow: const Money.rupees(2950),
          paymentAccountId: cash.id,
          lines: [
            ReturnLineDraft(documentLineId: sold.documentLineId, qty: Qty.one),
          ],
        ),
      );
      await shop.fbr.afterReturn(back.documentId);
      // The signal comes back and FBR answers, refusing the bill: the credit
      // note still has no number to name.
      clock.advance(const Duration(hours: 1));
      fbr.answer = const FbrRejected('0052', 'Buyer type missing.');
      await shop.fbr.sendPending();

      // A day and an hour later.
      clock.advance(const Duration(hours: 25));
      _bump(tester);
      await tester.pumpAndSettle();
      await tapText(tester, 'FBR: 1 offline bill der se. Abhi bhejein.');
      await _see(
        tester,
        find.textContaining(
          '1 connection aane ke 24 ghante baad bhi nahi gaye',
        ),
      );
      await _see(
        tester,
        find.text('Der: connection aane ke 24 ghante baad bhi nahi gaya'),
      );
    },
  );

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the MRP warning, the buyer\'s name and the PRA rows fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await app.services.counterTax.setServiceTax(
        ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra),
      );
      final pcs = await _pieces(app);
      for (final draft in [
        ItemDraft(
          name: 'Shampoo Anti-Dandruff 400ml',
          baseUnitId: pcs,
          saleRate: Rate.rupees(1300),
          mrp: const Money.rupees(1200),
          isThirdSchedule: true,
          openingStock: Qty.units(20),
        ),
        ItemDraft(
          name: 'Bridal makeup package',
          baseUnitId: pcs,
          saleRate: Rate.rupees(150000),
          tracksStock: false,
          isService: true,
        ),
      ]) {
        await app.services.catalogue.addItem(app.services.actorNow(), draft);
      }
      _bump(tester);

      await _ringUp(tester, 'Shampoo');
      await _ringUp(tester, 'Bridal', newBill: false);
      expect(find.textContaining('chhapi qeemat se zyada'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);

      await tapButton(tester, 'Paisay lein');
      await _payBy(tester, 'Card');
      await tester.pumpAndSettle();
      expect(find.text('Rs 1,63,300.00'), findsWidgets);
      await tester.ensureVisible(find.text('PRA 8% (card)'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.ensureVisible(find.text('CNIC (agar dein)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Khareedar ka naam: Rs 1 lakh se bara bill'),
        findsOneWidget,
      );
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}


Future<String> _pieces(Harness app) async {
  final firm = app.services.identity!.firmId;
  return (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs').id;
}

/// Tells every screen the books moved, as a save on a screen would.
void _bump(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
  listen: false,
).bumpRefresh();

/// Puts the first item [search] finds on the bill, opening the counter
/// first unless [newBill] is false, and leaves the bill showing.
Future<void> _ringUp(
  WidgetTester tester,
  String search, {
  bool newBill = true,
}) async {
  await tester.pumpAndSettle();
  if (newBill) await tapText(tester, 'Naya Bill');
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, search);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tester.enterText(field, '');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Picks how the bill is paid on the payment sheet.
Future<void> _payBy(WidgetTester tester, String mode) async {
  final chip = find.ancestor(
    of: find.text(mode),
    matching: find.byType(ChoiceChip),
  );
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and says it is there, once.
Future<void> _see(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(finder, findsOneWidget);
}
