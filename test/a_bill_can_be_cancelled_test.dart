import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Cancelling a bill, from the app.
///
/// The sales list has struck void bills through and badged them since M0,
/// waiting for something in `lib/` that could produce one. Nothing could. A
/// correction engine with no button is the same failure as a printer with no
/// button, and this repository has shipped that twice.
void main() {
  testWidgets('a posted bill offers to be cancelled', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);

    expect(find.byTooltip('Bill mansookh'), findsOneWidget);
  });

  testWidgets('cancelling writes the reversal and marks the bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _cancel(tester, 'Dobara ring ho gaya');

    final doc = await app.rowsOf('SELECT status, void_reason FROM documents');
    expect(
      doc.single['status'],
      'void',
      reason:
          'the Cancel button did nothing. Every printer artefact in this '
          'repository was in exactly that state for two commits.',
    );
    expect(doc.single['void_reason'], 'Dobara ring ho gaya');

    final reversals = await app.rowsOf(
      "SELECT id FROM journal_entries WHERE source_type = 'reversal'",
    );
    expect(reversals, hasLength(1));
  });

  testWidgets('the stock comes back on the shelf', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _cancel(tester, 'Maal wapas');

    // Twelve, the whole shelf. The opening was 12, the sale took 2, and the
    // void put them back — a figure of 10 would mean the goods stayed sold.
    final balance = await app.rowsOf(
      'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS b FROM stock_ledger',
    );
    expect(balance.single['b'], 12000);
  });

  testWidgets('the list strikes it through afterwards', (tester) async {
    // The treatment that has been waiting since M0 for something to produce
    // a void bill.
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _cancel(tester, 'Ghalti');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Mansookh'), findsOneWidget);
  });

  testWidgets('and stops offering to cancel it again', (tester) async {
    // An action that can only fail is one a shopkeeper learns to distrust the
    // whole screen for.
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _cancel(tester, 'Ghalti');

    // Back out and in again, because the sheet pops onto the receipt screen
    // rather than home, and reopening from where we are is not reopening.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openBill(tester);

    expect(find.byTooltip('Bill mansookh'), findsNothing);
  });

  testWidgets('a cancel with no reason is refused in words', (tester) async {
    // A void with no reason is a hole in the numbering nobody can account for
    // six months later.
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Bill mansookh'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan, mansookh karein');
    await tester.pumpAndSettle();

    expect(find.text('Wajah likhna zaroori hai'), findsOneWidget);
    final doc = await app.rowsOf('SELECT status FROM documents');
    expect(doc.single['status'], 'posted');
  });

  testWidgets('a bill paid against is refused, naming the receipt', (
    tester,
  ) async {
    // The refusal that matters, shown as words rather than dropped into a
    // stack trace. Naming the receipt is the whole point of the guard.
    final app = await Harness.startWithShop(tester);
    await _sell(app, onUdhaar: true);
    final receipt = await app.services.recordReceipt(
      app.services.actorNow(),
      ReceiptDraft(
        partyId: (await app.services.queries.searchParties(
          app.services.identity!.firmId,
        )).first.id,
        amount: const Money.rupees(100),
        mode: 'cash',
        paymentAccountId: (await app.services.queries.paymentAccounts(
          app.services.identity!.firmId,
        )).firstWhere((a) => a.isDefault).id,
      ),
    );

    await _openBill(tester);
    await _cancel(tester, 'Ghalti');

    expect(find.textContaining(receipt.paymentNo), findsOneWidget);
    final doc = await app.rowsOf('SELECT status FROM documents');
    expect(doc.single['status'], 'posted');
  });

  testWidgets('the sheet says the bill is not deleted', (tester) async {
    // A shopkeeper who believes a bill vanished will be surprised to find it
    // in a report, and being surprised by your own books is how you stop
    // trusting them.
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Bill mansookh'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bill mit-ta nahi'), findsOneWidget);
  });
}

Future<void> _openBill(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('INV-').first);
  await tester.pumpAndSettle();
}

Future<void> _cancel(WidgetTester tester, String reason) async {
  await tester.tap(find.byTooltip('Bill mansookh'));
  await tester.pumpAndSettle();
  await typeInto(tester, 'Wajah', reason);
  await tapText(tester, 'Haan, mansookh karein');
  await tester.pumpAndSettle();
}

/// One bill for two units at Rs 150, off a shelf of twelve.
Future<void> _sell(Harness app, {bool onUdhaar = false}) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Chawal Basmati',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(150),
      openingStock: Qty.units(12),
      openingRate: Rate.rupees(90),
    ),
  );

  String? partyId;
  if (onUdhaar) {
    partyId = await app.services.catalogue.addParty(
      actor,
      const PartyDraft(name: 'Rashid Traders', partyType: 'customer'),
    );
  }

  await app.services.postSale(
    actor,
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(2),
          baseQty: Qty.units(2),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: onUdhaar
          ? const []
          : [
              TenderDraft(
                paymentAccountId: (await app.services.queries.paymentAccounts(
                  firm,
                )).firstWhere((a) => a.isDefault).id,
                mode: 'cash',
                amount: const Money.rupees(300),
              ),
            ],
    ),
  );
}
