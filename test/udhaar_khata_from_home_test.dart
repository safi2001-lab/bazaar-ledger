import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/khata/chase_screen.dart';
import 'package:bazaar_ledger/features/khata/khata_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The udhaar khata, found from the first screen by its own name (M64).
///
/// The owner trying the app asked where the udhaar khata was. It had been
/// there all along, behind a tile called "Gahak"; a shopkeeper looks for the
/// book by the name they call it.
void main() {
  testWidgets('a new shop sees the udhaar khata on Home with nobody owing, '
      'and it opens the udhaar list', (tester) async {
    await Harness.startWithShop(tester);
    await tester.pumpAndSettle();

    expect(find.text('Udhaar Khata'), findsOneWidget);
    expect(find.text('Kisi se kuch lena nahi'), findsOneWidget);

    await tapText(tester, 'Udhaar Khata');
    await tester.pumpAndSettle();
    expect(find.byType(ChaseScreen), findsOneWidget);
  });

  testWidgets('a customer who owes is counted on the card with the total, and '
      'their khata is two taps from Home', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _owes(app, 'Rashid Kiryana', 1250);
    await tester.pumpAndSettle();
    _refresh(tester);
    await tester.pumpAndSettle();

    expect(find.text('1 gahak se lena hai'), findsOneWidget);
    expect(find.textContaining('1,250.00'), findsWidgets);

    await tapText(tester, 'Udhaar Khata');
    await tester.pumpAndSettle();
    expect(find.byType(ChaseScreen), findsOneWidget);

    await tapText(tester, 'Rashid Kiryana');
    await tester.pumpAndSettle();
    expect(find.byType(KhataScreen), findsOneWidget);
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the udhaar khata card fits with a six-figure total', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(720, 1600)
        ..devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final app = await Harness.startWithShop(tester);
      await _owes(app, 'Chaudhry Muhammad Aslam Karyana Store', 123456);
      _refresh(tester);
      await tester.pumpAndSettle();

      expect(find.text('Udhaar Khata'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final element in find.byType(Text).evaluate()) {
        final box = element.renderObject! as RenderBox;
        if (!box.hasSize || box.size.isEmpty) continue;
        final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
        expect(
          right,
          lessThanOrEqualTo(width + 0.5),
          reason: '"${(element.widget as Text).data}" runs off the screen',
        );
      }
    });
  });
}

/// Home re-reads its figures, as it does after any save on screen.
void _refresh(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
).bumpRefresh();

/// A customer who owes [rupees] on one udhaar bill.
Future<void> _owes(Harness app, String name, int rupees) async {
  final id = await app.services.catalogue.addParty(
    app.services.actorNow(),
    PartyDraft(name: name),
  );
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final itemId = await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Item $name',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(10),
    ),
  );
  await app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: id,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Item',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: const [],
    ),
  );
}
