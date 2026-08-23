import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Chasing udhaar from the app.
///
/// WhatsApp itself cannot be driven from a host test — it is another
/// application on another process. What these check is everything either side
/// of it: that the button appears only when there is something to chase, that
/// what would be handed over is addressed to the right number and says the
/// right amount, and that a shop with no number for a customer is told so
/// rather than shown a chat with nobody.
///
/// The message and the number are asserted in pk_domain, where they are pure.
/// These prove the app reaches them.
void main() {
  testWidgets('a customer who owes nothing is not chased', (tester) async {
    // The button is the ask. Offering it against a settled customer is how a
    // shop annoys somebody who paid last week.
    final app = await Harness.startWithShop(tester);
    await _customer(app, phone: '0300-4471203');

    await _openKhata(tester);

    expect(find.byTooltip('Yaad dilayein'), findsNothing);
  });

  testWidgets('a customer who owes is chaseable', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _customer(app, phone: '0300-4471203');
    await _sellOnUdhaar(app, rupees: 4500);

    await _openKhata(tester);

    expect(find.byTooltip('Yaad dilayein'), findsOneWidget);
  });

  testWidgets('a customer with no number falls back, and says so', (
    tester,
  ) async {
    // Plenty of khata entries are a name and nothing else. The message still
    // exists and the shopkeeper may want to read it out, so the share sheet
    // is offered rather than the whole thing being refused.
    final sheet = _RecordingShareSheet()..install();
    addTearDown(sheet.remove);

    final app = await Harness.startWithShop(tester);
    await _customer(app, phone: null);
    await _sellOnUdhaar(app, rupees: 4500);

    await _openKhata(tester);
    await tester.tap(find.byTooltip('Yaad dilayein'));
    await tester.pumpAndSettle();

    expect(find.text('Is gahak ka number nahi hai'), findsOneWidget);
    expect(sheet.texts, hasLength(1));
    expect(sheet.texts.single, contains('4,500.00'));
    expect(sheet.texts.single, contains('Rashid Traders'));
  });

  test('the reminder is addressed to a number WhatsApp can reach', () {
    // The failure this replaces is silent: `0300-4471203` handed to WhatsApp
    // unchanged opens a chat with nobody, and the shopkeeper believes the
    // message went.
    expect(whatsappNumber('0300-4471203'), '923004471203');
    expect(whatsappNumber('042-35761234'), isNull);
  });

  test('the app never opens a browser to send a reminder', () {
    // On the code, not the file's text.
    //
    // The first version of this asserted the file did not contain "wa.me" and
    // failed, because the comment above the scheme explains at length why
    // wa.me is not used. A test that reads prose as configuration is a test
    // that fires on its own documentation — the third time in this repository
    // that exact shape has come up, after READ_MEDIA_IMAGES in a manifest
    // comment and no_phantom_gate firing on its own rationale.
    final code = _code('lib/features/khata/send_reminder.dart');

    expect(code, contains('whatsapp://send'));
    expect(
      code,
      isNot(contains('wa.me')),
      reason:
          'a reminder would reach Meta over the network for a shop with no '
          'WhatsApp installed',
    );
    expect(
      code,
      isNot(contains('api.whatsapp.com')),
      reason: 'the Business API is an account, a token and a server',
    );
  });

  test('the manifest can still see whether WhatsApp is installed', () {
    // canLaunchUrl answers from <queries>. Without the block it returns false
    // on Android 11 and above however installed WhatsApp is, and every
    // reminder silently falls back to the share sheet.
    final manifest = _source('android/app/src/main/AndroidManifest.xml');

    final queried = RegExp(
      r'<package\s+android:name="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toSet();
    expect(queried, containsAll(['com.whatsapp', 'com.whatsapp.w4b']));

    // On the DECLARED permissions, for the same reason as above: the manifest
    // names QUERY_ALL_PACKAGES in the comment explaining why it uses a narrow
    // <queries> block instead.
    final declared = RegExp(
      r'<uses-permission\s+android:name="([^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toSet();
    expect(
      declared,
      isNot(contains('android.permission.QUERY_ALL_PACKAGES')),
      reason: 'Play treats that as a sensitive permission needing a review',
    );
  });
}

/// A Dart file with its comments stripped.
///
/// Whole-line comments only. Cutting at the first `//` anywhere on a line
/// strips the inside of `whatsapp://send` too, which is how the first
/// version of this managed to assert the scheme was missing from the file
/// that contains it.
String _code(String path) => _source(
  path,
).split('\n').where((line) => !line.trimLeft().startsWith('//')).join('\n');

String _source(String path) => File(path).readAsStringSync();

Future<void> _openKhata(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tester.pumpAndSettle();
  await tapText(tester, 'Rashid Traders');
  await tester.pumpAndSettle();
}

Future<String> _customer(Harness app, {required String? phone}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(name: 'Rashid Traders', partyType: 'customer', phone: phone),
    );

Future<void> _sellOnUdhaar(Harness app, {required int rupees}) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final partyId = (await app.services.queries.searchParties(firm)).first.id;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(10),
    ),
  );

  await app.services.postSale(
    actor,
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil 5L',
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

/// Stands in for the system share sheet. See receipt_shares_as_pdf_test for
/// why this is injected at the platform seam rather than the method channel.
final class _RecordingShareSheet {
  static const _channel = MethodChannel('dev.fluttercommunity.plus/share');

  final texts = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final arguments = call.arguments;
          if (arguments is Map && arguments['text'] is String) {
            texts.add(arguments['text'] as String);
          }
          return 'dev.fluttercommunity.plus/share/success';
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}
