import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/items/item_editor.dart';
import 'package:bazaar_ledger/features/pharmacy/near_expiry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The pharmacy pack through the screens (M49).
///
/// The rules hold beneath every screen (`pk_data`'s and `pk_bootstrap`'s
/// tests prove the refusals); these prove the chemist meets them at the
/// counter in his own words first: a medicine found by its salt, the DRAP
/// price refused before the bill is written, a Schedule medicine asking for
/// the prescription, a held batch refused at the scan, the near-expiry list
/// sending its batches back to the supplier, and the shop saying it is a
/// pharmacy in its details.
void main() {
  testWidgets('a medicine is found at the counter by its salt, and its '
      'substitutes are on its page', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _isAPharmacy(app, tester);
    await _medicine(app, 'Panadol', generic: 'Paracetamol', onHand: 0);
    await _medicine(app, 'Calpol', generic: 'Paracetamol', onHand: 30);
    await _medicine(app, 'Brufen', generic: 'Ibuprofen', strength: '400 mg');

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _search(tester, 'paracetamol');
    expect(find.text('Panadol'), findsOneWidget);
    expect(find.text('Calpol'), findsOneWidget);
    expect(find.text('Brufen'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Panadol').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Calpol'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ItemEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('ISI SALT KI DAWAIYAN: PARACETAMOL 500 MG'),
      findsOneWidget,
    );
    expect(find.text('Calpol'), findsOneWidget);
    expect(find.text('30 pcs'), findsOneWidget, reason: 'with its stock');
  });

  testWidgets('a pharmacy is refused a medicine above its printed price at '
      'the counter, and nothing is written', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _isAPharmacy(app, tester);
    await _medicine(app, 'Disprin', rupees: 55, mrp: 50, onHand: 20);

    await _ring(tester, 'Disprin');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '55');
    await tapButton(tester, 'Save karein');

    expect(find.text('DRAP qeemat se zyada'), findsOneWidget);
    expect(
      find.textContaining('MRP sirf Rs 50.00 ki ijazat deti hai'),
      findsOneWidget,
    );
    await tester.tap(find.text('Theek hai'));
    await tester.pumpAndSettle();
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      0,
    );
  });

  testWidgets('a Schedule medicine asks for the prescription, and the bill is '
      'saved with it in the register', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _isAPharmacy(app, tester);
    await _medicine(
      app,
      'Xanax 0.5',
      generic: 'Alprazolam',
      strength: '0.5 mg',
      schedule: ScheduleClass.b,
      onHand: 20,
    );

    await _ring(tester, 'Xanax');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '40');
    await tapButton(tester, 'Save karein');

    expect(find.text('DOCTOR KA NUSKHA'), findsOneWidget);
    expect(
      find.text(
        'Schedule dawai: Xanax 0.5. Sirf registered doctor ke nuskhe par '
        'bikti hai.',
      ),
      findsOneWidget,
    );
    await tapButton(tester, 'Aage barhein');
    expect(
      find.text('Yeh khana zaroori hai'),
      findsWidgets,
      reason: 'not without the patient and the prescriber',
    );
    expect(await app.countIn('prescriptions'), 0);

    await typeInto(tester, 'Mareez ka naam', 'Bilal Ahmed');
    await typeInto(tester, 'Doctor ka naam', 'Dr Ayesha Khan');
    await typeInto(tester, 'Doctor ka PM&DC registration no.', '12345-P');
    await tapButton(tester, 'Aage barhein');
    await tester.pumpAndSettle();

    expect(
      await app.rowsOf(
        'SELECT patient_name, prescriber_name, prescriber_reg_no '
        'FROM prescriptions',
      ),
      [
        {
          'patient_name': 'Bilal Ahmed',
          'prescriber_name': 'Dr Ayesha Khan',
          'prescriber_reg_no': '12345-P',
        },
      ],
    );
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      1,
    );
  });

  testWidgets('a pack from a batch on hold is refused at the scan, with the '
      'reason', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _isAPharmacy(app, tester);
    final services = app.services;
    final panadol = await _medicine(
      app,
      'Panadol strip',
      batches: true,
      barcode: '8960123456789',
    );
    final supplier = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );
    await _receive(app, panadol, supplier, 'B42', '2027-06-30');
    final firm = (await services.queries.currentFirm())!;
    final lot = (await services.queries.lotsOnHand(firm.id)).single;
    await services.pharmacy.holdBatch(lot.lotId, 'DRAP recall');

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Talash karein').first;
    await tester.enterText(field, '01089601234567891727063010B42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.text('Batch B42 roka hua hai: DRAP recall. Yeh na bechein.'),
      findsOneWidget,
    );
    expect(find.text('Panadol strip'), findsNothing);
  });

  testWidgets('near expiry by supplier: the batches are ticked and go back to '
      'the supplier', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _isAPharmacy(app, tester);
    final services = app.services;
    final panadol = await _medicine(app, 'Panadol', batches: true);
    final supplier = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );
    await _receive(app, panadol, supplier, 'EXP1', '2026-10-20');

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expiry qareeb — supplier war'));
    await tester.pumpAndSettle();
    expect(find.byType(NearExpiryScreen), findsOneWidget);
    expect(find.text('MEDI DISTRIBUTORS · RS 600.00'), findsOneWidget);
    expect(find.text('EXP1 · 20 pcs'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'batch supplier ko wapas');
    await tester.tap(find.widgetWithText(FilledButton, 'Wapas bhejein'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wapsi ho gayi'), findsOneWidget);
    expect(find.text('Un ke khate se Rs 600.00 kam'), findsOneWidget);
    expect(
      await app.scalar<int>(
        'SELECT COALESCE(SUM(s.qty_delta_thousandths), 0) FROM stock_ledger s '
        "JOIN stock_lots l ON l.id = s.lot_id WHERE l.lot_no = 'EXP1'",
      ),
      0,
    );
  });

  testWidgets('the shop says it is a pharmacy in its details, with its '
      'discount off the MRP, and the counter rings it', (tester) async {
    final app = await Harness.startWithShop(tester);
    await openSettings(tester);
    await tapText(tester, 'Dukan ki tafseel');

    final kind = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(kind);
    await tester.pumpAndSettle();
    await tester.tap(kind);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medical store').last);
    await tester.pumpAndSettle();
    await typeInto(tester, 'Har dawai par MRP se % kam', '10');
    await tapButton(tester, 'Save karein');

    final rules = await app.services.pharmacy.rules();
    expect(rules.isPharmacy, isTrue);
    expect(rules.offMrpBp, 1000);

    // Back from Settings to the counter.
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    await _medicine(app, 'Disprin', rupees: 50, mrp: 50, onHand: 20);
    await _ring(tester, 'Disprin');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '45');
    await tapButton(tester, 'Save karein');
    expect(
      await app.scalar<int>(
        "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      4500,
      reason: 'Rs 50 MRP, 10% off',
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the prescription and the near-expiry list fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _isAPharmacy(app, tester);
      final services = app.services;
      await _medicine(
        app,
        'Xanax 0.5 Alprazolam Tablets',
        generic: 'Alprazolam',
        schedule: ScheduleClass.b,
        onHand: 20,
      );
      final panadol = await _medicine(
        app,
        'Panadol Extra Advance Tablets',
        batches: true,
      );
      final supplier = await services.catalogue.addParty(
        services.actorNow(),
        const PartyDraft(
          name: 'Medi Distributors Lahore (Pvt) Ltd',
          partyType: 'supplier',
        ),
      );
      await _receive(app, panadol, supplier, 'EXP-2026-10-B42', '2026-10-20');

      await _ring(tester, 'Xanax');
      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '40');
      await tapButton(tester, 'Save karein');
      expect(find.text('DOCTOR KA NUSKHA'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maal').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expiry qareeb — supplier war'));
      await tester.pumpAndSettle();
      expect(find.byType(NearExpiryScreen), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
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


/// The shop says it is a pharmacy, and the screens hear of it, as they do
/// when the shop's details are saved.
Future<void> _isAPharmacy(Harness app, WidgetTester tester) async {
  await app.services.updateFirm({'business_kind': 'pharmacy'});
  ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).first),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}

Future<String> _medicine(
  Harness app,
  String name, {
  String? generic,
  String strength = '500 mg',
  ScheduleClass? schedule,
  int rupees = 40,
  int? mrp,
  int onHand = 0,
  bool batches = false,
  String? barcode,
}) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final pcs = (await services.queries.units(
    firm.id,
  )).firstWhere((u) => u.code == 'pcs');
  return services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(rupees),
      mrp: mrp == null ? null : Money.rupees(mrp),
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(20),
      tracksBatch: batches,
      barcode: barcode,
      medicine: MedicineDetails(
        genericName: generic,
        strength: generic == null ? null : strength,
        schedule: schedule,
      ),
    ),
  );
}

Future<void> _receive(
  Harness app,
  String itemId,
  String supplier,
  String batch,
  String expiry,
) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final pcs = (await services.queries.units(
    firm.id,
  )).firstWhere((u) => u.code == 'pcs');
  await services.recordPurchase(
    services.actorNow(),
    PurchaseDraft(
      partyId: supplier,
      lines: [
        PurchaseLineDraft(
          itemId: itemId,
          itemName: 'Medicine',
          qty: Qty.units(20),
          baseQty: Qty.units(20),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(30),
          batchNo: batch,
          expiry: BusinessDate(expiry),
        ),
      ],
    ),
  );
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _ring(WidgetTester tester, String query) async {
  await tester.pumpAndSettle();
  if (find.text('Naya Bill').evaluate().isNotEmpty) {
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
  }
  await _search(tester, query);
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
