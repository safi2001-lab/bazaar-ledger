import 'package:bazaar_ledger/features/items/low_stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The two M1 features a shopkeeper could not reach.
///
/// Both were built, both were tested, and neither was wired to anything.
///
///   * `lowStockItems` had two tests and a place in the 20,000-SKU performance
///     fixture. `stockLowTitle`, `stockLowNone`, `stockLowSubtitle` and
///     `stockLowFloor` sat in both ARB files. Nothing under `lib/features/`
///     referenced any of the five, so no shopkeeper ever saw an item running
///     low. A commit called that milestone work done.
///   * `searchItems` and `recentSales` both take `afterId`, the keyset paging
///     is measured against 20,000 rows, and neither caller passed it. The
///     sales list carried a hard `limit: 60`.
///
/// These tests drive the widget tree. A test that called the query directly
/// would have passed throughout the period when the feature was unreachable —
/// which is precisely what the existing query tests did.
void main() {
  testWidgets('a shopkeeper can see what is about to run out', (tester) async {
    final app = await Harness.startWithShop(tester);
    final firm = app.services.identity!.firmId;
    final actor = app.services.actorNow();

    final pcs = (await app.services.queries.units(
      firm,
    )).firstWhere((u) => u.code == 'pcs');

    // One item below its floor, one comfortably above. Only the first belongs
    // on this screen.
    await app.services.catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Chai Patti',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(450),
        tracksStock: true,
        openingStock: Qty.units(2),
        minStock: Qty.units(10),
      ),
    );
    await app.services.catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Cheeni',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(160),
        tracksStock: true,
        openingStock: Qty.units(80),
        minStock: Qty.units(10),
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Kam stock');
    await tester.pumpAndSettle();

    expect(find.byType(LowStockScreen), findsOneWidget);
    expect(
      find.text('Chai Patti'),
      findsOneWidget,
      reason:
          'an item below its floor is not on the low-stock screen, which '
          'is the only reason the screen exists',
    );
    expect(
      find.text('Cheeni'),
      findsNothing,
      reason:
          'an item with plenty left is being reported as running low, so '
          'the list is noise and a shopkeeper will stop reading it',
    );

    // The floor is shown, because "2 left" means nothing without it.
    expect(find.textContaining('Hadd:'), findsWidgets);

    expect(
      find.text('Sab theek hai'),
      findsNothing,
      reason: 'the all-clear is showing while something is short',
    );
  });

  testWidgets(
    'nothing running low says so, rather than showing an empty list',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final actor = app.services.actorNow();
      final firm = app.services.identity!.firmId;
      final pcs = (await app.services.queries.units(
        firm,
      )).firstWhere((u) => u.code == 'pcs');
      await app.services.catalogue.addItem(
        actor,
        ItemDraft(
          name: 'Cheeni',
          baseUnitId: pcs.id,
          saleRate: Rate.rupees(160),
          tracksStock: true,
          openingStock: Qty.units(80),
          minStock: Qty.units(10),
        ),
      );

      await tester.pumpAndSettle();
      await tapText(tester, 'Kam stock');
      await tester.pumpAndSettle();

      // Nothing is wrong, and the shopkeeper should be told that plainly rather
      // than shown a blank page or a prompt to go and add something.
      expect(find.text('Sab theek hai'), findsOneWidget);
    },
  );

  testWidgets('the item list pages past the first forty', (tester) async {
    final app = await Harness.startWithShop(tester);
    final actor = app.services.actorNow();
    final firm = app.services.identity!.firmId;
    final pcs = (await app.services.queries.units(
      firm,
    )).firstWhere((u) => u.code == 'pcs');

    // Fifty. One page is forty, so the fiftieth is only reachable if the
    // cursor is actually being passed.
    for (var i = 1; i <= 50; i++) {
      await app.services.catalogue.addItem(
        actor,
        ItemDraft(
          name: 'Cheez ${i.toString().padLeft(3, '0')}',
          baseUnitId: pcs.id,
          saleRate: Rate.rupees(100 + i),
        ),
      );
    }

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();

    // The first page is on screen and the last item is not.
    expect(find.text('Cheez 001'), findsOneWidget);
    expect(find.text('Cheez 050'), findsNothing);

    // Scroll to the bottom, which is what asks for the next page.
    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, -4000),
      800,
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, -4000),
      800,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cheez 050'),
      findsOneWidget,
      reason:
          'the list stops at forty items. A shop with twenty thousand '
          'SKUs can search but cannot browse, and the keyset paging that was '
          'built and measured for exactly this is still unreachable.',
    );
  });
}
