import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Quotations, from the counter to the bill.
///
/// A wholesaler's customer asks for a price on forty cartons in the
/// morning and rings back at four to take them. The price was written
/// down as a quotation; the bill is made from it at that price, even if
/// the shelf price moved in between.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);

  testWidgets('a cart is kept as a quotation and nothing leaves the shelf', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _ringUpOil(tester);
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Quotation banayein');

    final q = await app.rowsOf(
      'SELECT doc_type, doc_no, total_paisa, party_name_snapshot '
      'FROM documents',
    );
    expect(q.single['doc_type'], 'quotation');
    expect(q.single['total_paisa'], 250000);
    expect(q.single['party_name_snapshot'], 'Rashid Traders');
    expect(await app.countIn('stock_ledger'), 1, reason: 'opening stock only');
    expect(await app.countIn('payments'), 0);
    expect(find.text('Quotation ${q.single['doc_no']} ban gayi'), findsOne);
  });

  testWidgets('a quotation is billed at the price quoted', (tester) async {
    final app = await Harness.startWithShop(tester);
    final oil = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _ringUpOil(tester);
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Quotation banayein');

    // The shelf price goes up after the price was given.
    await app.services.catalogue.updateItem(
      app.services.actorNow(),
      oil,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: (await app.services.queries.itemById(
          app.services.identity!.firmId,
          oil,
        ))!.unitId,
        saleRate: Rate.rupees(2700),
      ),
    );

    await _home(tester);
    await tapText(tester, 'Quotation');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Is se bill banayein');
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    final bill = await app.rowsOf(
      "SELECT id, total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['total_paisa'], 250000, reason: 'the quoted price');
    final link = await app.rowsOf(
      'SELECT link_type, to_document_id FROM doc_links',
    );
    expect(link.single['link_type'], 'converted_from');
    expect(link.single['to_document_id'], bill.single['id']);
  });

  testWidgets('a billed quotation says so and cannot be billed again', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _ringUpOil(tester);
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Quotation banayein');
    await _home(tester);
    await tapText(tester, 'Quotation');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Is se bill banayein');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '2500');
    await tapButton(tester, 'Save karein');

    final billNo = await app.scalar<String>(
      "SELECT doc_no FROM documents WHERE doc_type = 'sale_invoice'",
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Quotation');
    expect(find.text('Bill $billNo ban gaya'), findsOneWidget);
    await tapText(tester, 'Rashid Traders');
    expect(find.text('Is se bill banayein'), findsNothing);
  });

  testWidgets('a quotation is shared as a PDF titled Quotation', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await _ringUpOil(tester);
    await tapButton(tester, 'Quotation banayein');
    final docNo = await app.scalar<String>('SELECT doc_no FROM documents');

    await _home(tester);
    await tapText(tester, 'Quotation');
    await tapText(tester, 'Aam gahak');
    await tester.tap(find.text('PDF bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    final text = String.fromCharCodes(
      File(_sheet.paths.single).readAsBytesSync(),
    );
    expect(text, contains('Quotation $docNo'));
  });
}

/// Back from the counter to the home screen.
Future<void> _home(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _ringUpOil(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Cooking',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Paisay lein');
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
