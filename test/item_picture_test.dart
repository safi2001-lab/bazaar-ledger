import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A photograph on an item.
///
/// Worth more here than in most catalogues: national literacy is around 60%
/// and rural literacy near 50%, so a cashier who cannot read a name fluently
/// can still recognise a packet. It is the same reasoning behind the icons,
/// the big numerals and the colour-coded direction everywhere else.
///
/// The picking itself is a system dialog and cannot be driven from a host
/// test. What these check is everything either side of it: that a photograph
/// survives the round trip through the shop's own database, that it comes back
/// small, and that the control is not offered where it could not work.
void main() {
  testWidgets('a photograph survives the round trip and comes back small', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final itemId = await _item(app);

    // A camera-sized original: 1600x1200 is what the picker hands over after
    // its own first pass, and eight megabytes is what a phone produces before
    // that.
    await app.services.pictures.setItemPicture(
      app.services.actorNow(),
      itemId: itemId,
      source: _photo(1600, 1200),
      fileName: 'oil.jpg',
    );

    final stored = await app.services.pictures.itemPicture(
      app.services.identity!.firmId,
      itemId,
    );

    expect(stored, isNotNull);
    expect(
      stored!.bytes.length,
      lessThanOrEqualTo(ImageAttachment.maxBytes),
      reason:
          'the picture went in at full size, which turns a shop backup '
          'into a file nobody can send over WhatsApp',
    );
    expect(stored.width, ImageAttachment.maxEdge);
    expect(
      img.decodeJpg(stored.bytes),
      isNotNull,
      reason: 'what came back is not a readable picture',
    );
  });

  testWidgets('a new item is not offered a photograph it cannot keep', (
    tester,
  ) async {
    // A picture needs a row to hang off. Offering the control before the item
    // is saved would either lose the photograph or need somewhere to park it,
    // and a control that sometimes does nothing teaches a shopkeeper to
    // distrust every control.
    await Harness.startWithShop(tester);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapButton(tester, 'Naya maal');
    await tester.pumpAndSettle();

    expect(find.text('Tasveer lagayein'), findsNothing);
  });

  testWidgets('an existing item offers one, and shows it once set', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final itemId = await _item(app);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Cooking Oil 5L');
    await tester.pumpAndSettle();
    expect(find.text('Tasveer lagayein'), findsOneWidget);

    // Set one behind the screen, since the picker itself is a system dialog.
    await app.services.pictures.setItemPicture(
      app.services.actorNow(),
      itemId: itemId,
      source: _photo(800, 600),
      fileName: 'oil.jpg',
    );

    // Reopen: the field reads what is stored when it is built.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Cooking Oil 5L');
    await tester.pumpAndSettle();

    expect(find.text('Tasveer badlein'), findsOneWidget);
    expect(find.text('Tasveer hatayein'), findsOneWidget);
  });

  testWidgets('a file that is not a picture is refused in words', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final itemId = await _item(app);

    await expectLater(
      app.services.pictures.setItemPicture(
        app.services.actorNow(),
        itemId: itemId,
        source: Uint8List.fromList([37, 80, 68, 70]), // "%PDF"
        fileName: 'invoice.pdf',
      ),
      throwsA(isA<FormatException>()),
    );

    // And nothing was stored, so the item is not left with half a picture.
    expect(
      await app.services.pictures.itemPicture(
        app.services.identity!.firmId,
        itemId,
      ),
      isNull,
    );
  });

  test('photographing a tin of oil costs the Play listing nothing', () {
    // The system Photo Picker needs no permission at all. READ_MEDIA_IMAGES is
    // restricted by Play to apps whose core function the picker cannot serve,
    // and a billing app asking for it would go through a declaration review in
    // order to let a shopkeeper photograph a packet.
    //
    // This test first asserted CAMERA was absent too, and camera barcode
    // scanning later made that false — correctly. The assertion had conflated
    // two different claims: "photographs need no permission", which is still
    // true and is what this test is for, and "the app has no camera", which
    // was only ever incidentally true. The gate caught the difference.
    final declared = RegExp(
      r'<uses-permission\s+android:name="([^"]+)"',
    ).allMatches(_manifest()).map((m) => m.group(1)!).toSet();

    expect(declared, isNot(contains('android.permission.READ_MEDIA_IMAGES')));
    expect(
      declared,
      isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
    );
    expect(
      declared,
      isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')),
    );
  });
}

String _manifest() =>
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

Future<String> _item(Harness app) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(1450),
    ),
  );
}

/// A photograph-shaped image: gradients with structure, which is what a camera
/// produces and what JPEG is designed for.
Uint8List _photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        x * 255 ~/ width,
        y * 255 ~/ height,
        ((x + y) ~/ 8) % 256,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
