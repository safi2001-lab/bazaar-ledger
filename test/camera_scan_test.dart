import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Scanning a packet with the phone camera.
///
/// The camera is a platform surface and cannot be driven from a host test — no
/// amount of pumping produces a frame with a barcode in it. What these check
/// is everything either side of it: that the control is reachable from the two
/// places a shopkeeper would look for it, that a scanned code lands on the
/// bill through the SAME path a hardware wedge uses, and that asking for a
/// camera costs the Play listing exactly one ordinary runtime permission.
///
/// The scan screen itself is deliberately thin for this reason. It pops a
/// string and knows nothing about items, so the part that can go wrong — the
/// lookup, the UPC-A widening, adding to the cart — is all in code a host test
/// can reach.
void main() {
  testWidgets('the counter offers the camera when nothing is typed', (
    tester,
  ) async {
    // Most shops in this bracket do not own a USB gun: it is four thousand
    // rupees on top of a printer, and the phone is already in hand.
    await Harness.startWithShop(tester);

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Barcode scan karein'), findsOneWidget);
  });

  testWidgets('and gives the slot back to clear once something is typed', (
    tester,
  ) async {
    // One slot, because a cashier reaches for one or the other and the counter
    // has no room to spare beside a search field on a 720-wide screen.
    final app = await Harness.startWithShop(tester);
    await _stock(app, name: 'Cooking Oil 5L', barcode: '012345678905');

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Cooking');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Barcode scan karein'), findsNothing);
  });

  testWidgets('a scanned code reaches the bill through the wedge path', (
    tester,
  ) async {
    // The camera and the gun end in the same place on purpose. Two lookups
    // would be two places for the UPC-A widening to be got right and one place
    // for it to be forgotten.
    //
    // Submitting the field is exactly what a wedge does: it types fast and
    // presses Enter.
    final app = await Harness.startWithShop(tester);
    await _stock(app, name: 'Cooking Oil 5L', barcode: '012345678905');

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();

    // Thirteen digits — what a camera reports for a twelve-digit packet.
    await tester.enterText(find.byType(TextFormField).first, '0012345678905');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      find.text('Cooking Oil 5L'),
      findsWidgets,
      reason:
          'a packet entered as a twelve-digit UPC could not be found by '
          'the thirteen digits a camera reports, so the cashier would add it '
          'again by hand',
    );
  });

  testWidgets('the item editor can read a barcode instead of typing it', (
    tester,
  ) async {
    // Thirteen digits typed by hand at a counter is where a catalogue gets its
    // wrong barcodes, and a wrong barcode is worse than none: it silently
    // matches the wrong packet at the till.
    final app = await Harness.startWithShop(tester);
    await _stock(app, name: 'Cooking Oil 5L', barcode: null);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Cooking Oil 5L');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Barcode scan karein'), findsOneWidget);
  });

  test('the camera costs one ordinary runtime permission, and no more', () {
    // On the DECLARED permissions, not on the file's text.
    //
    // The first version of this asserted the manifest did not contain the
    // string READ_MEDIA_IMAGES — and it failed, because the comment above the
    // camera permission explains at length why READ_MEDIA_IMAGES is not there.
    // A test that reads prose as configuration is a test that fires on its own
    // documentation, which is the same shape as citing an enforcement rule
    // that does not exist.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    final declared = RegExp(
      r'<uses-permission\s+android:name="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toSet();

    // CAMERA is runtime-dangerous, not a Play RESTRICTED permission: no
    // declaration form, only an honest listing and a privacy policy.
    expect(declared, contains('android.permission.CAMERA'));

    // Exactly two, and each has a feature behind it. A permission with no
    // feature makes the Play Data Safety form a lie.
    expect(
      declared,
      {'android.permission.INTERNET', 'android.permission.CAMERA'},
      reason:
          'the app manifest declares something no feature needs, or is '
          'missing something a feature does',
    );

    // Not REQUIRED as a feature, so the listing stays visible to a phone with
    // no rear camera. Those still exist at the bottom of this market, and a
    // shop with a hardware gun has no use for it anyway.
    final features = RegExp(
      r'<uses-feature\s+android:name="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toSet();
    expect(features, contains('android.hardware.camera'));
    expect(manifest, contains('android:required="false"'));
  });

  test('ML Kit is bundled, not downloaded on first use', () {
    // The unbundled variant is ~3 MB smaller and fetches its model through
    // Play Services the first time somebody scans — which is exactly the
    // moment a shop with a patchy connection is standing at the counter with
    // a customer waiting. It fails there, silently, on day one.
    //
    // Paying the megabytes is the offline-first argument applied to a
    // dependency, and the flag that would undo it is a single line in
    // gradle.properties.
    final properties = File('android/gradle.properties').readAsStringSync();
    expect(
      properties,
      isNot(contains('useUnbundled=true')),
      reason:
          'the barcode model would be downloaded on first use, which is '
          'the one moment a shop cannot rely on a connection',
    );
  });
}

Future<String> _stock(
  Harness app, {
  required String name,
  required String? barcode,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: name,
      barcode: barcode,
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(1450),
      openingStock: Qty.units(20),
    ),
  );
}
