import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The books closed up to a day, a PIN before anything is undone, and a
/// bill's history — from the screen (M42).
void main() {
  testWidgets(
    'the owner closes the books from settings, and a bill dated inside them '
    'asks for the PIN and a reason on screen',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final services = app.services;
      await services.setPin(services.currentUser!.id, '1947');
      final oil = await _shelve(app);
      final suggested = await services.audit.suggestedCloseDate();

      await openSettings(tester);
      await tapText(tester, 'Hisaab band aur Data Lock');
      expect(find.text('Abhi koi din band nahi'), findsOneWidget);
      await tapButton(tester, '${suggested.value} tak band karein');

      expect(
        find.text('${suggested.value} tak hisaab band hai'),
        findsOneWidget,
      );
      expect(
        (await services.audit.locks()).closedThrough?.value,
        suggested.value,
      );

      // A bill dated on the closed day, the way a counter whose date was set
      // wrong would ring it.
      final pending = _sell(app, oil, on: suggested);
      await tester.pumpAndSettle();
      expect(find.text('Hisaab band hai'), findsOneWidget);

      await typeInto(tester, 'PIN', '1947');
      await typeInto(tester, 'Wajah (zaroori)', 'Purana bill drawer mein mila');
      await tapButton(tester, 'Ijazat dein');
      final bill = await pending;

      final doc = await app.rowsOf(
        "SELECT doc_date_local FROM documents WHERE doc_no = '${bill.docNo}'",
      );
      expect(doc.single['doc_date_local'], suggested.value);
      final log = await app.rowsOf(
        'SELECT summary FROM audit_log '
        "WHERE action_code = 'CLOSED_BOOKS_OVERRIDDEN'",
      );
      expect(log.single['summary'], contains('Purana bill drawer mein mila'));
      expect((await services.checkHealth()).isHealthy, isTrue);
    },
  );

  testWidgets(
    "with Data Lock on, cancelling a bill asks for a PIN, and the bill's "
    'history shows the cancel and why',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final services = app.services;
      await services.setPin(services.currentUser!.id, '1947');
      await services.audit.setDataLock(on: true);
      await _sell(app, await _shelve(app));

      await tester.pumpAndSettle();
      await tapText(tester, 'Farokht');
      await tester.tap(find.textContaining('INV-').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bill mansookh'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'Wajah', 'Dobara ring ho gaya');
      final confirm = find.text('Haan, mansookh karein');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await _frames(tester);

      // The write path asked; the prompt is up over the cancel sheet, whose
      // button is still turning underneath it.
      expect(find.text('Data Lock: PIN chahiye'), findsOneWidget);
      await _answer(tester, '1111');
      expect(find.text('Ghalat PIN'), findsOneWidget);
      await _answer(tester, '1947');
      await tester.pumpAndSettle();

      final doc = await app.rowsOf('SELECT status, void_reason FROM documents');
      expect(doc.single['status'], 'void');

      // Back to the home screen, and in through the activity log.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapText(tester, 'Kaun ne kya kiya');
      await tester.tap(find.textContaining('Voided INV-').first);
      await tester.pumpAndSettle();

      expect(find.text('Banaya gaya'), findsOneWidget);
      expect(find.text('Cancel hua'), findsOneWidget);
      expect(find.text('Wajah: Dobara ring ho gaya'), findsOneWidget);
      expect(find.text('PIN se ijazat'), findsOneWidget);
      expect(find.textContaining('Malik Sahib'), findsWidgets);
    },
  );
}

/// Cooking oil on the shelf since two months ago, so a bill dated back
/// sells stock that was there.
Future<String> _shelve(Harness app) async {
  final services = app.services;
  final pcs = (await services.queries.units(
    services.identity!.firmId,
  )).firstWhere((u) => u.code == 'pcs');
  final actor = services.actorNow();
  return services.catalogue.addItem(
    actor.at(actor.startedAtUtc.subtract(const Duration(days: 62))),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(2500),
      openingStock: Qty.units(10),
      openingRate: Rate.rupees(2100),
    ),
  );
}

/// One bottle of [oil] for cash, now or as of [on].
Future<PostedSale> _sell(Harness app, String oil, {BusinessDate? on}) async {
  final services = app.services;
  final firm = services.identity!.firmId;
  final pcs = (await services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  var actor = services.actorNow();
  if (on != null) {
    actor = actor.at(DateTime.utc(on.year, on.month, on.day, 5));
  }
  final cash = (await services.queries.paymentAccounts(
    firm,
  )).firstWhere((a) => a.modeLabel == 'cash');
  return services.postSale(
    actor,
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(2500),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(2500),
        ),
      ],
    ),
  );
}

/// Lets a few frames through. Not `pumpAndSettle`: while the prompt is up the
/// sheet underneath shows a spinner, which never settles.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Types [pin] into the prompt and allows.
Future<void> _answer(WidgetTester tester, String pin) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'PIN').last, pin);
  await tester.pump();
  await tester.tap(
    find
        .ancestor(of: find.text('Ijazat dein'), matching: find.byType(BlButton))
        .last,
  );
  await _frames(tester);
}
