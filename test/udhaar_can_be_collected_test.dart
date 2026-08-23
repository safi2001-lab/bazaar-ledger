import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Taking money off a customer's khata, from the app.
///
/// The reason this suite exists at all: `PrintQueue`, `TcpPrinter` and the
/// whole Kotlin plugin sat in this repository for two commits with zero call
/// sites in `lib/`, and two commits announced them as shipped. A payment path
/// with no button is the same thing in a different package.
///
/// So these drive the actual screens: tap a customer, see what they owe, take
/// money, and read the database afterwards.
void main() {
  testWidgets('a customer name opens their khata, not a form', (tester) async {
    // Tapping a customer used to open the editor — a form for their phone
    // number and credit limit. That is the second thing a shopkeeper wants
    // from a name in a khata. The first is how much.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);

    await _openKhata(tester);

    expect(find.text('Kitna lena hai'), findsOneWidget);
    expect(find.text('Paisay wasool karein'), findsWidgets);
  });

  testWidgets('the khata shows what is owed and on which bills', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);
    await _sellOnUdhaar(app, rupees: 1500);

    await _openKhata(tester);

    expect(find.text('Rs 4,500.00'), findsOneWidget);
    expect(find.text('Khule bill'), findsOneWidget);
    // Without the currency symbol: a column of amounts does not repeat it,
    // and only the headline balance is prefixed.
    //
    // findsWidgets rather than findsOneWidget, because the history below the
    // open bills legitimately shows the same figures again — once as what is
    // owed on the bill, once as what the bill was for.
    expect(find.text('3,000.00'), findsWidgets);
    expect(find.text('1,500.00'), findsWidgets);
  });

  testWidgets('a payment reaches the database and the balance comes down', (
    tester,
  ) async {
    // The whole point. A button that opens a sheet and writes nothing is the
    // failure this file is named after.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);
    await _sellOnUdhaar(app, rupees: 1500);

    await _openKhata(tester);
    await _receive(tester, '3200');

    final payments = await app.rowsOf(
      'SELECT amount_paisa, direction, mode FROM payments',
    );
    expect(
      payments,
      hasLength(1),
      reason:
          'the Save button did nothing. Every printer artefact in this '
          'repository was in exactly that state for two commits.',
    );
    expect(payments.single['amount_paisa'], 320000);
    expect(payments.single['direction'], 'in');

    final allocations = await app.rowsOf(
      'SELECT amount_paisa FROM payment_allocations ORDER BY amount_paisa DESC',
    );
    expect(allocations, hasLength(2));
    expect(allocations.first['amount_paisa'], 300000);
    expect(allocations.last['amount_paisa'], 20000);

    final open = await app.rowsOf(
      'SELECT balance_paisa FROM documents ORDER BY balance_paisa',
    );
    expect(open.map((r) => r['balance_paisa']), [0, 130000]);
  });

  testWidgets('the khata shows what was paid, not only what is owed', (
    tester,
  ) async {
    // The question a customer actually asks is "I paid you last week", and
    // the answer has to be a date, an amount and a receipt number they can
    // match against the paper in their hand. The open-bills view answers a
    // different question.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);

    await _openKhata(tester);
    await _receive(tester, '1000');
    await tester.pumpAndSettle();

    expect(find.text('Purana hisaab'), findsOneWidget);
    expect(find.textContaining('RCV-'), findsOneWidget);
    expect(find.textContaining('INV-'), findsWidgets);

    // Signed, so a payment is visibly money coming back. The glyph is a real
    // minus sign, not a hyphen: a hyphen beside a figure reads as part of an
    // invoice number at a glance.
    expect(find.text('− Rs 1,000.00'), findsWidgets);
  });

  testWidgets('the sheet says which bills it will clear, before saving', (
    tester,
  ) async {
    // The single most-complained-about gap in the competing products: a
    // shopkeeper who cannot say which bills a payment settled cannot argue
    // about it with a customer either.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);
    await _sellOnUdhaar(app, rupees: 1500);

    await _openKhata(tester);
    await tapText(tester, 'Paisay wasool karein');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '3200');
    await tester.pumpAndSettle();

    expect(find.text('Yeh bill saaf honge'), findsOneWidget);
    // One bill cleared, one only reduced — and the difference is shown,
    // because "part paid" is the half of the answer that starts arguments.
    expect(find.text('Ho gaya'), findsOneWidget);
    expect(find.text('Khule bill'), findsWidgets);
  });

  testWidgets('paying more than is owed is offered as credit, not refused', (
    tester,
  ) async {
    // A customer settling up and rounding to the next thousand. Ordinary, and
    // an app that refuses it sends them away with their money.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay wasool karein');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '5000');
    await tester.pumpAndSettle();

    expect(find.text('Jama (advance)'), findsOneWidget);

    await tapText(tester, 'Wasooli save karein');
    await tester.pumpAndSettle();

    final payments = await app.rowsOf('SELECT amount_paisa FROM payments');
    expect(payments.single['amount_paisa'], 500000);

    final advance = await app.rowsOf(
      'SELECT SUM(jl.credit_paisa - jl.debit_paisa) AS net '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'customer_advances'",
    );
    expect(advance.single['net'], 200000);
  });

  testWidgets('a customer with nothing owed can still be paid on account', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _party(app);

    await _openKhata(tester);
    await tapText(tester, 'Paisay wasool karein');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '2000');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Koi khula bill nahi'),
      findsOneWidget,
      reason: 'the sheet promised to settle bills that do not exist',
    );
  });

  testWidgets('an amount of nothing is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay wasool karein');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pumpAndSettle();
    await tapText(tester, 'Wasooli save karein');
    await tester.pumpAndSettle();

    expect(find.text('Raqam likhein'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM payments'), isEmpty);
  });

  testWidgets('a cheque with no number is refused in words', (tester) async {
    // The schema refuses it too, three layers down, as a constraint name.
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay wasool karein');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1000');
    await tapText(tester, 'Cheque');
    await tester.pumpAndSettle();
    await tapText(tester, 'Wasooli save karein');
    await tester.pumpAndSettle();

    expect(find.text('Cheque number likhein'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM payments'), isEmpty);
  });
}

/// Opens the khata for the one customer in the shop.
Future<void> _openKhata(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tester.pumpAndSettle();
  await tapText(tester, 'Rashid Traders');
  await tester.pumpAndSettle();
}

/// Fills in the sheet and saves.
Future<void> _receive(WidgetTester tester, String amount) async {
  await tapText(tester, 'Paisay wasool karein');
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, amount);
  await tester.pumpAndSettle();
  await tapText(tester, 'Wasooli save karein');
  await tester.pumpAndSettle();
}

Future<String> _party(Harness app) async {
  final existing = await app.services.queries.searchParties(
    app.services.identity!.firmId,
  );
  if (existing.isNotEmpty) return existing.first.id;

  return app.services.catalogue.addParty(
    app.services.actorNow(),
    const PartyDraft(name: 'Rashid Traders', partyType: 'customer'),
  );
}

/// One bill, entirely on udhaar.
Future<void> _sellOnUdhaar(Harness app, {required int rupees}) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final partyId = await _party(app);

  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Cooking Oil $rupees',
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
          itemName: 'Cooking Oil $rupees',
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
