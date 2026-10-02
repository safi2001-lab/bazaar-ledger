import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The bill finder on the smallest screen it ships to, font all the way up
/// (M30).
///
/// The sales list gained a search box, two rows of filters and a send button
/// on every row, all on a 360dp phone that a shopkeeper reads at 200%. A
/// six-figure total beside a send button is exactly the shape that painted
/// past the edge of the screen on the counter, so it is checked the way
/// large_text_test checks the counter: with a real font, on the geometry.
void main() {
  setUpAll(_loadRealFont);

  testWidgets('the sales list, its filters and the send sheet fit a small '
      'phone at 200%', (tester) async {
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
    final firm = app.services.identity!.firmId;
    final rashid = await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Rashid Traders', phone: '0300-4471203'),
    );
    final pcs = (await app.services.queries.units(
      firm,
    )).firstWhere((u) => u.code == 'pcs');
    final drum = await app.seedItem(name: 'Ghee Drum', rupees: 125000);
    // Rs 5,00,000 on udhaar: the widest total and the widest chip together.
    await app.services.postSale(
      app.services.actorNow(),
      SaleDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        lines: [
          SaleLineDraft(
            itemId: drum,
            itemName: 'Ghee Drum',
            qty: Qty.units(4),
            baseQty: Qty.units(4),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(125000),
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Farokht');
    await tester.pumpAndSettle();
    _expectNothingPaintsOffScreen(tester);

    await tester.tap(find.byTooltip('Bhejein'));
    await tester.pumpAndSettle();
    _expectNothingPaintsOffScreen(tester);
  });
}

/// Every rendered box, still inside the screen it was drawn on. The same
/// check as large_text_test's, for the same reason: a Container whose child
/// is wider than it says nothing at all and paints past the display.
///
/// Except what sits in a sideways-scrolling row, which is off the edge by
/// design and a swipe away: the filter chips.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final inSidewaysRow =
        element
            .findAncestorWidgetOfExactType<SingleChildScrollView>()
            ?.scrollDirection ==
        Axis.horizontal;
    if (inSidewaysRow) continue;
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

/// A real font, because the test font draws every glyph as a square of one
/// width and every overflow test passes against it.
Future<void> _loadRealFont() async {
  for (final path in [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
