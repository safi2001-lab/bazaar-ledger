import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

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
  setUpAll(_loadRealFont);

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

/// Loads a real font, because the default test font lies about width.
///
/// `flutter_test` renders every glyph as an identical box in Ahem, so a string
/// that overflows a real screen measures narrow enough to fit and every
/// overflow test passes vacuously. The Flutter SDK ships Roboto, so there is
/// nothing to vendor.
Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(
        file.readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    await loader.load();
    return;
  }
  // No system font to borrow. Say so rather than passing on Ahem's square
  // glyphs, which would make every assertion here meaningless.
  fail(
    'no real font found to measure text with; this suite cannot prove '
    'anything against the test font',
  );
}
