import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Delivery challans, from the counter to the bill.
///
/// The van leaves on Monday with forty cartons for a retailer who is billed
/// on Saturday. The goods leave the shelf with the challan; the bill made
/// from it later takes nothing more off the shelf, and a challan whose goods
/// came back is cancelled and puts them back.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);

  testWidgets('goods sent on a challan leave the shelf and owe nothing', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    final rashid = await app.seedParty(name: 'Rashid Traders');

    await _sendOil(tester);

    final c = await app.rowsOf(
      'SELECT doc_type, doc_no, total_paisa, balance_paisa FROM documents',
    );
    expect(c.single['doc_type'], 'delivery_challan');
    expect(c.single['total_paisa'], 250000);
    expect(c.single['balance_paisa'], 0);
    expect(await app.countIn('stock_ledger'), 2, reason: 'opening, then out');
    final firm = await app.services.queries.currentFirm();
    final party = await app.services.queries.partyById(firm!.id, rashid);
    expect(party!.balance, Money.zero);
    expect(
      find.text('Challan ${c.single['doc_no']} ban gaya, maal nikal gaya'),
      findsOne,
    );
  });

  testWidgets('a challan with no customer is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await _ringUpOil(tester);
    await tapButton(tester, 'Challan banayein');

    expect(
      find.text('Challan par gahak ka naam zaroori hai. Pehle gahak chunein.'),
      findsOne,
    );
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('a bill made from a challan takes nothing more off the shelf', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _sendOil(tester);
    await _home(tester);
    await tapText(tester, 'Challan');
    expect(find.text('Bill baqi hai'), findsOne);
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Is se bill banayein');
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    final bill = await app.rowsOf(
      "SELECT id, balance_paisa FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['balance_paisa'], 250000);
    expect(await app.countIn('stock_ledger'), 2, reason: 'no second exit');
    final parked = await app.scalar<int>(
      'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'goods_on_challan'",
    );
    expect(parked, 0);
  });

  testWidgets('goods that came back cancel the challan', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _sendOil(tester);
    await _home(tester);
    await tapText(tester, 'Challan');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Maal wapas aa gaya');
    expect(find.textContaining('wapas shelf par aa jaye ga'), findsOne);
    await tapButton(tester, 'Maal wapas aa gaya');

    final onShelf = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
    );
    final opening = await app.scalar<int>(
      "SELECT qty_delta_thousandths FROM stock_ledger WHERE txn_type = 'opening'",
    );
    expect(onShelf, opening);
    expect(
      await app.scalar<String>(
        "SELECT status FROM documents WHERE doc_type = 'delivery_challan'",
      ),
      'void',
    );
    expect(find.text('Maal wapas aa gaya'), findsOne, reason: 'the chip');
  });

  testWidgets('a week of challans to one customer is billed on one bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _sendOil(tester);
    await _sendOil(tester);
    await _home(tester);
    await tapText(tester, 'Challan');
    await tester.tap(find.text('Rashid Traders').first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Is gahak ke 1 aur challan bhi isi bill mein');
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    final bill = await app.rowsOf(
      "SELECT id, total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['total_paisa'], 500000);
    expect(
      await app.scalar<int>(
        'SELECT COUNT(*) FROM doc_links WHERE to_document_id = '
        "'${bill.single['id']}'",
      ),
      2,
    );
    expect(await app.countIn('stock_ledger'), 3, reason: 'no third exit');
  });

  testWidgets('a challan is shared as a PDF titled Delivery Challan', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _sendOil(tester);
    final docNo = await app.scalar<String>('SELECT doc_no FROM documents');

    await _home(tester);
    await tapText(tester, 'Challan');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.text('PDF bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    final text = String.fromCharCodes(
      File(_sheet.paths.single).readAsBytesSync(),
    );
    expect(text, contains('Delivery Challan $docNo'));
  });
}

/// Rings up the oil for Rashid Traders and sends it on a challan.
Future<void> _sendOil(WidgetTester tester) async {
  await _ringUpOil(tester);
  await tapText(tester, 'Aam gahak');
  await tapText(tester, 'Rashid Traders');
  await tapButton(tester, 'Challan banayein');
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
