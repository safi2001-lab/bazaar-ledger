import 'package:bazaar_ledger/app/preferences.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/design/text_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The app on the smallest screen it ships to, with the font turned all the
/// way up.
///
/// A shopkeeper's phone is a cracked 720x1600 Infinix held at arm's length,
/// and Android's font-size slider goes to 200%. Five rounds of auditing walked
/// past a whole class of overflow here because `flutter_test` invents an
/// 800x600 viewport and renders every glyph as a square of a fixed width — so
/// text that overruns a real phone fits the test perfectly.
///
/// These tests load the real Roboto and lay the app out at 360x800 logical
/// pixels. What they caught: the bill total painted 93dp past the right edge
/// of the screen in the tender sheet, and 18dp past it on the counter, because
/// a `FittedBox` that is a non-flex child of a `Row` is given unbounded width
/// and never scales anything. `BlCard` does not clip and `Text` raises no
/// overflow assertion, so in release the cashier simply read "Rs 12,500."
/// aloud off a bill for Rs 12,500.75.
void main() {
  setUpAll(loadRealFont);

  /// 360x800 dp — an Infinix Smart at its 720x1600 native resolution.
  void useASmallPhone(WidgetTester tester, {double textScale = 2}) {
    tester.view
      ..physicalSize = const Size(720, 1600)
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  /// Every rendered box, still inside the screen it was drawn on.
  ///
  /// `takeException` alone is not enough. A `RenderFlex` reports an overflow,
  /// but a `Container` whose child is simply wider than it is says nothing at
  /// all — it paints past its own edge and past the display, silently. So the
  /// geometry is checked directly.
  void expectNothingPaintsOffScreen(WidgetTester tester) {
    expect(tester.takeException(), isNull);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final element in find.byType(Text).evaluate()) {
      final box = element.renderObject! as RenderBox;
      if (!box.hasSize || box.size.isEmpty) continue;
      // Through the transform, not by adding the width. A `FittedBox` scales
      // its child with a transform layer and leaves the child's own `size` at
      // its natural, unscaled value — so `left + size.width` reports an
      // overflow for text that is in fact scaled down and entirely on screen.
      final left = box.localToGlobal(Offset.zero).dx;
      final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
      expect(
        right,
        lessThanOrEqualTo(width + 0.5),
        reason: '"${(element.widget as Text).data}" is painted from $left to '
            '$right on a $width dp screen — the tail of it is not on the '
            'phone at all',
      );
      expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
    }
  }

  testWidgets('the counter fits a small phone at 200%', (tester) async {
    useASmallPhone(tester);
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L Tin', rupees: 12500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');

    // The running total, the per-line quantity and the rate all live in the
    // same few rows, and all three were broken.
    expectNothingPaintsOffScreen(tester);
  });

  testWidgets('the tender sheet fits a small phone at 200%', (tester) async {
    useASmallPhone(tester);
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L Tin', rupees: 12500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tapButton(tester, 'Paisay lein');

    expectNothingPaintsOffScreen(tester);

    // And with change showing, which adds a second money row to the card.
    await typeInto(tester, 'Diye gaye', '20000');
    await tester.pumpAndSettle();
    expectNothingPaintsOffScreen(tester);
  });

  testWidgets('the home screen fits a small phone at 200% on its first '
      'morning', (tester) async {
    useASmallPhone(tester);
    await Harness.startWithShop(tester);

    // The zero-sales state, which is what every shop sees before the first
    // bill of the day: the "Koi bill nahi" chip was cut off at the edge.
    expectNothingPaintsOffScreen(tester);
  });

  testWidgets('the counter can take money sideways, without a scroll a '
      'finger cannot perform', (tester) async {
    // A tablet on the counter is the standard Pakistani retail setup and
    // main.dart unlocks every orientation on purpose. Sideways with the
    // keyboard up there are about 160dp of body left.
    //
    // This test previously passed against a layout where the Charge button
    // was genuinely unreachable. It used the harness `tapButton`, which calls
    // `ensureVisible` first — performing programmatically a scroll no finger
    // could perform, because the cart list filled the fold and won every
    // gesture so the scroll view underneath it never moved. So this one never
    // calls `ensureVisible`: it asserts the button is inside the viewport and
    // then taps it where it is.
    tester.view
      ..physicalSize = const Size(1600, 720)
      ..devicePixelRatio = 2
      ..viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    final app = await Harness.startWithShop(tester);
    for (var i = 0; i < 8; i++) {
      await app.seedItem(name: 'Cooking Oil 5L Tin $i', rupees: 2500);
    }

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await _addToCart(tester, 'Cooking Oil 5L Tin $i');
    }

    expect(tester.takeException(), isNull, reason: 'the body overflowed');

    final charge = find
        .ancestor(
          of: find.textContaining('Paisay lein'),
          matching: find.byType(BlButton),
        )
        .first;

    final rect = tester.getRect(charge);
    final screen =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height),
      reason: 'the Charge button is laid out below the bottom of the screen, '
          'at $rect on a $screen display',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(screen.width),
      reason: 'the Charge button is off the right of the screen at $rect',
    );

    // Tapped where it is. No ensureVisible, no scrolling, nothing a person
    // with one hand and a customer waiting could not do.
    await tester.tap(charge);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Diye gaye'),
      findsOneWidget,
      reason: 'the tender sheet never opened, so the button was not tappable',
    );
  });

  testWidgets('the khata list shows customer names at 200%', (tester) async {
    useASmallPhone(tester);
    final app = await Harness.startWithShop(tester);
    for (final name in const [
      'Bilal General Store',
      'Chishti Traders Wholesale',
    ]) {
      await app.seedParty(name: name, owedRupees: 125000);
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gahak').first);
    await tester.pumpAndSettle();

    // The balance chip was a non-flex child of the row, so it took its full
    // natural width first — 204dp of a 360dp screen — and left the name about
    // two glyphs and an ellipsis. Every debtor rendered as the same
    // unreadable stub, and only for the shopkeepers who turned the font up
    // because they could not read the small one.
    for (final name in const ['Bilal', 'Chishti']) {
      final finder = find.textContaining(name);
      expect(finder, findsOneWidget, reason: '$name is not on the screen');
      final box = tester.renderObject<RenderBox>(finder);
      expect(
        box.size.width,
        greaterThan(110),
        reason: 'the name column is only ${box.size.width}dp wide, which is '
            'a couple of characters',
      );
    }
    expectNothingPaintsOffScreen(tester);
  });

  testWidgets('a cart line can be corrected sideways', (tester) async {
    // The counter is autofocused for the barcode scanner, so the soft
    // keyboard is up the moment the screen opens. Letting it shrink the body
    // sideways left about 100dp for a search field, a bill and a totals
    // panel — and the cart line was laid out BELOW the fold, so the tap to
    // correct a quantity did not land on it at all. Nothing overflowed and
    // nothing threw; the line was simply not reachable.
    tester.view
      ..physicalSize = const Size(1600, 720)
      ..devicePixelRatio = 2
      ..viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      '',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // With the keyboard up, the money path is what has to be reachable. A
    // 360dp-tall phone minus a 200dp keyboard, an app bar and a search field
    // leaves about 14dp: that does not fit a bill, and no layout can make it.
    // What it must fit is the total and the button that takes the money.
    final visibleBottom = tester.view.physicalSize.height /
            tester.view.devicePixelRatio -
        tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    final charge = find
        .ancestor(
          of: find.textContaining('Paisay lein'),
          matching: find.byType(BlButton),
        )
        .first;
    expect(
      tester.getRect(charge).bottom,
      lessThanOrEqualTo(visibleBottom),
      reason: 'the Charge button is behind the keyboard at '
          '${tester.getRect(charge)}',
    );

    // Now the shopkeeper puts the keyboard away to look at the bill, which is
    // what anyone does. The line has to be reachable then.
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();

    final line = find
        .ancestor(of: find.byType(BlQty), matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(line).bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
      reason: 'the cart line is off the bottom of the screen at '
          '${tester.getRect(line)}',
    );

    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(
      find.text('Ho gaya'),
      findsOneWidget,
      reason: 'the line editor did not open',
    );

    // And it can be confirmed: the sheet scrolls, so the buttons are
    // reachable even with the keyboard over them.
    await tester.dragUntilVisible(
      find.text('Ho gaya'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho gaya'));
    await tester.pumpAndSettle();
    expect(find.text('Ho gaya'), findsNothing);
  });

  testWidgets("the shop's Larger text on a phone already at 200% is held at "
      '200%, and the counter still fits', (tester) async {
    // M56: the app's own text size goes on top of the phone's. Two hundred
    // percent times Larger would be 260%, past anything these screens were
    // laid out for, so the two together are held at 200%.
    useASmallPhone(tester);
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        initialPreferencesProvider.overrideWithValue(
          AppPreferences(
            locale: const Locale('ur'),
            themeMode: ThemeMode.light,
            textSize: BlTextSize.larger,
          ),
        ),
      ],
    );
    await app.seedItem(name: 'Cooking Oil 5L Tin', rupees: 12500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');

    final scaler = MediaQuery.textScalerOf(
      tester.element(find.text('Cooking Oil 5L Tin').first),
    );
    expect(scaler.scale(10), 20, reason: 'held at 200%, not 260%');
    expectNothingPaintsOffScreen(tester);

    await tapButton(tester, 'Paisay lein');
    expectNothingPaintsOffScreen(tester);
  });

  testWidgets('a six-figure bill still fits at 200%', (tester) async {
    useASmallPhone(tester);
    final app = await Harness.startWithShop(tester);
    // Rs 1,25,000 a tin, four tins: a wholesale bill, and the widest the
    // money formatter gets before crore.
    await app.seedItem(name: 'Ghee Drum', rupees: 125000);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await _addToCart(tester, 'Ghee');
    }
    await tapButton(tester, 'Paisay lein');

    expectNothingPaintsOffScreen(tester);
  });
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

