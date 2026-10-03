import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/mobile/phone_story_screen.dart';
import 'package:bazaar_ledger/features/mobile/qist_sheet.dart';
import 'package:bazaar_ledger/features/mobile/used_phone_screen.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The mobile-shop pack through the screens (M50).
///
/// The rules hold beneath every screen (`pk_data`'s and `pk_bootstrap`'s
/// tests prove the refusals and the books); these prove the shopkeeper meets
/// them at the phone first, in his own words: a phone found by the last
/// digits of its second IMEI with its whole story, a mistyped IMEI refused
/// before a used phone is bought, a phone PTA has called non-compliant said
/// at the counter, and a phone sold on qist with its schedule shown before
/// it is saved.
void main() {
  const imeiA = '356938035643809';
  const imeiA2 = '356938035643817';
  const imeiB = '861234056789012';
  const mistyped = '356938035643808';

  testWidgets('a phone is found by the last digits of its second IMEI, and '
      "its story says where it came from, its warranty and PTA's answer", (
    tester,
  ) async {
    final app = await _mobileShop(tester);
    final shop = await _Shop.seed(app);
    await shop.receive(const [
      PhoneUnitDraft(imei1: imeiA, imei2: imeiA2, pta: PtaStatus.approved),
    ]);
    final rashid = await app.seedParty(name: 'Rashid Ali');
    await shop.sell(imeiA, partyId: rashid, cash: 60000);

    await tapText(tester, 'Phone dhoondein');
    await typeInto(tester, 'IMEI (poora, ya aakhri hindsay)', '43817');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('IMEI 2: $imeiA2'), findsOneWidget);
    expect(find.text('Dukaan mein nahi'), findsOneWidget);
    await tapText(tester, 'Samsung A15');

    expect(find.text('IMEI 1: $imeiA\nIMEI 2: $imeiA2'), findsOneWidget);
    expect(find.text('PTA approved'), findsWidgets);
    expect(find.text('3 Oct 2027 tak warranty'), findsWidgets);
    expect(find.text('Warranty mein'), findsOneWidget);
    expect(find.text('Company warranty'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Rashid Ali ko becha'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Hall Road Distributors se khareeda'), findsOneWidget);
    expect(find.text('Rashid Ali ko becha'), findsOneWidget);
  });

  testWidgets('a used phone with a mistyped IMEI is refused in words, and a '
      'good one goes on the shelf and into the register', (tester) async {
    final app = await _mobileShop(tester);
    await _Shop.seed(app);

    await tapText(tester, 'Phone dhoondein');
    await tapButton(tester, 'Purana phone khareedein');
    await typeInto(tester, 'Bechne wale ka CNIC', '35202-1234567-1');
    await typeInto(tester, 'Bechne wale ka naam', 'Kashif Mehmood');
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samsung A15').last);
    await tester.pumpAndSettle();
    await typeInto(tester, 'IMEI 1', mistyped);
    await typeInto(tester, 'Bechne wale ko diye', '18000');
    await tapButton(tester, 'Khareedein aur stock mein daalein');

    expect(
      find.text(
        'IMEI $mistyped ghalat likha hai: aakhri hindsa 9 hona chahiye. '
        'Dabbe se ya *#06# se dobara likhein.',
      ),
      findsOneWidget,
    );
    expect(await app.countIn('used_phone_buys'), 0);
    expect(await app.countIn('stock_lots'), 0, reason: 'nothing written');

    await typeInto(tester, 'IMEI 1', imeiB);
    await tapButton(tester, 'Khareedein aur stock mein daalein');
    await settleReal(tester, until: find.textContaining('purane phone'));
    expect(find.textContaining('purane phone register'), findsOneWidget);
    expect(
      find.text('BECHNE WALE KE CNIC KI TASVEER'),
      findsOneWidget,
      reason: 'the photographs go on once there is something to hang them on',
    );
    final row = await app.rowsOf(
      'SELECT seller_name, seller_cnic FROM used_phone_buys',
    );
    expect(row.single, {
      'seller_name': 'Kashif Mehmood',
      'seller_cnic': '3520212345671',
    });
    final firm = (await app.services.queries.currentFirm())!;
    expect(
      (await app.services.queries.serialOnHand(firm.id, imeiB))?.lotNo,
      imeiB,
    );
  });

  testWidgets('at the counter the last five digits of a phone IMEI put it on '
      'the bill, and two phones that answer are offered to pick from', (
    tester,
  ) async {
    final app = await _mobileShop(tester);
    final shop = await _Shop.seed(app);
    await shop.receive(const [
      PhoneUnitDraft(imei1: imeiA, pta: PtaStatus.approved),
      PhoneUnitDraft(imei1: '357777700000005', pta: PtaStatus.approved),
      PhoneUnitDraft(imei1: '867777711111117', pta: PtaStatus.approved),
    ]);
    List<String> onTheBill() => ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    ).read(cartProvider).lines.expand((l) => l.lotLabels).toList();

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, '43809');
    expect(onTheBill(), [imeiA], reason: 'one phone answers, straight on');

    // Four digits are not enough to go looking among the phones.
    await _scan(tester, '3809');
    expect(onTheBill(), [imeiA]);

    // Two phones hold "77777": the counter asks which.
    await _scan(tester, '77777');
    expect(
      find.text('Dukaan ke phone jin ke IMEI mein 77777 hai'),
      findsOneWidget,
    );
    await tester.tap(find.text('IMEI: 867777711111117'));
    await tester.pumpAndSettle();
    expect(onTheBill(), [imeiA, '867777711111117']);
  });

  testWidgets('a delivery of phones takes each with its second IMEI, and a '
      'mistyped one is refused before the line is added', (tester) async {
    final app = await _mobileShop(tester);
    await _Shop.seed(app);

    await tapText(tester, 'Kharidari');
    await tapText(tester, 'Nayi kharidari');
    await tapText(tester, 'Supplier chunein');
    await tapText(tester, 'Hall Road Distributors');
    await tapText(tester, 'Cheez shamil karein');
    await typeInto(tester, 'Talash karein', 'Samsung');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Samsung A15');
    await typeInto(tester, 'Serial / IMEI (har line mein ek)', mistyped);
    await typeInto(tester, 'Kharid qeemat', '100000');
    Future<void> addLine() async {
      final add = find
          .ancestor(
            of: find.text('Cheez shamil karein'),
            matching: find.byType(BlButton),
          )
          .last;
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
    }

    await addLine();
    expect(
      find.textContaining('ghalat likha hai: aakhri hindsa 9'),
      findsOneWidget,
    );

    await typeInto(
      tester,
      'Serial / IMEI (har line mein ek)',
      '$imeiA / $imeiA2\n$imeiB',
    );
    await addLine();
    await tapText(tester, 'Kharidari save karein');

    final lots = await app.rowsOf(
      'SELECT serial, serial_2, pta_status FROM stock_lots ORDER BY serial',
    );
    expect(lots, [
      {'serial': imeiA, 'serial_2': imeiA2, 'pta_status': 'unknown'},
      {'serial': imeiB, 'serial_2': null, 'pta_status': 'unknown'},
    ]);
  });

  testWidgets('a phone PTA called non-compliant is said at the counter before '
      'it goes on the bill', (tester) async {
    final app = await _mobileShop(tester);
    final shop = await _Shop.seed(app);
    await shop.receive(const [
      PhoneUnitDraft(imei1: imeiB, pta: PtaStatus.nonCompliant),
    ]);

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, imeiB);
    expect(find.text('PTA non-compliant'), findsOneWidget);
    expect(find.textContaining('60 din mein block'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Samsung A15'), findsNothing, reason: 'not on the bill');

    await _scan(tester, imeiB);
    await tester.tap(find.text('Bechein, customer ko pata hai'));
    await tester.pumpAndSettle();
    expect(find.text('Samsung A15'), findsOneWidget);
  });

  testWidgets('a phone sold on qist at the counter shows its schedule before '
      'it is saved, and the plan is written with the bill', (tester) async {
    final app = await _mobileShop(tester);
    final shop = await _Shop.seed(app);
    await shop.receive(const [
      PhoneUnitDraft(imei1: imeiA, pta: PtaStatus.approved),
    ]);
    await app.seedParty(name: 'Rashid Traders');

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, imeiA);
    await tapButton(tester, 'Paisay lein');
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Qist par bechein');
    await typeInto(tester, 'Qist ka munafa (Rs)', '5000');
    await typeInto(tester, 'Abhi naqd advance (Rs)', '10000');
    await typeInto(tester, 'Qistein', '11');
    await typeInto(tester, 'Har mahine ki tareekh', '5');
    expect(find.text('11 x Rs 5,000.00'), findsOneWidget);
    await tapButton(tester, 'Qist par save karein');
    await settleReal(tester, until: find.textContaining('Qist markup'));
    // The paper names the markup as what it is, and says the plan.
    expect(find.textContaining('Qist markup'), findsWidgets);
    expect(find.textContaining('11 x Rs 5,000.00'), findsWidgets);

    final plan = await app.rowsOf(
      'SELECT down_payment_paisa, markup_paisa, financed_paisa, '
      'instalment_count, due_day FROM qist_plans',
    );
    expect(plan.single, {
      'down_payment_paisa': 1000000,
      'markup_paisa': 500000,
      'financed_paisa': 5500000,
      'instalment_count': 11,
      'due_day': 5,
    });
    expect(await app.countIn('qist_instalments'), 11);
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets("a phone's story, the used phone form and the qist sheet fit", (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await _mobileShop(tester);
      final shop = await _Shop.seed(app);
      await shop.receive(const [
        PhoneUnitDraft(imei1: imeiA, imei2: imeiA2, pta: PtaStatus.approved),
      ]);
      await app.seedParty(name: 'Rashid Traders Hall Road');

      await tapText(tester, 'Phone dhoondein');
      await typeInto(tester, 'IMEI (poora, ya aakhri hindsay)', imeiA);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, 'Samsung A15');
      expect(find.byType(PhoneStoryScreen), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapButton(tester, 'Purana phone khareedein');
      expect(find.byType(UsedPhoneScreen), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Naya Bill').last);
      await tester.pumpAndSettle();
      await _scan(tester, imeiA);
      await tapButton(tester, 'Paisay lein');
      await tapText(tester, 'Aam gahak');
      await tapText(tester, 'Rashid Traders Hall Road');
      await tapButton(tester, 'Qist par bechein');
      await typeInto(tester, 'Abhi naqd advance (Rs)', '10000');
      expect(find.byType(QistSheet), findsOneWidget);
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


/// The shop says it is a mobile shop, and the screens follow.
Future<Harness> _mobileShop(WidgetTester tester) async {
  final app = await Harness.startWithShop(
    tester,
    shopName: 'Hafeez Centre Mobiles',
    clock: FixedClock(DateTime.utc(2026, 10, 3, 5)),
  );
  await app.services.updateFirm({'business_kind': 'mobile'});
  ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).first),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  return app;
}

/// A phone model, kept by IMEI with a brand year's warranty, and the
/// distributor phones come from.
final class _Shop {
  _Shop(this.app, this.firmId, this.pcs, this.item, this.distributor);

  final Harness app;
  final String firmId;
  final String pcs;
  final String item;
  final String distributor;

  static Future<_Shop> seed(Harness app) async {
    final services = app.services;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs').id;
    final item = await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Samsung A15',
        baseUnitId: pcs,
        saleRate: Rate.rupees(60000),
        tracksSerial: true,
        warranty: const ItemWarranty(months: 12, kind: WarrantyKind.brand),
      ),
    );
    final distributor = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Hall Road Distributors', partyType: 'supplier'),
    );
    return _Shop(app, firm.id, pcs, item, distributor);
  }

  Future<void> receive(List<PhoneUnitDraft> phones) => app.services
      .recordPurchase(
        app.services.actorNow(),
        PurchaseDraft(
          partyId: distributor,
          lines: [
            PurchaseLineDraft(
              itemId: item,
              itemName: 'Samsung A15',
              qty: Qty.units(phones.length),
              baseQty: Qty.units(phones.length),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(50000),
              phones: phones,
            ),
          ],
        ),
      )
      .then((_) {});

  Future<void> sell(String imei, {String? partyId, int cash = 0}) async {
    final services = app.services;
    final lot = (await services.queries.serialOnHand(firmId, imei))!;
    final account = (await services.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    await services.postSale(
      services.actorNow(),
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: item,
            itemName: 'Samsung A15',
            qty: Qty.one,
            baseQty: Qty.one,
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(60000),
            lotId: lot.lotId,
          ),
        ],
        tenders: [
          if (cash > 0)
            TenderDraft(
              paymentAccountId: account.id,
              mode: 'cash',
              amount: Money.rupees(cash),
            ),
        ],
      ),
    );
  }
}

Future<void> _scan(WidgetTester tester, String code) async {
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}
