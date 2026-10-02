import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// "Ghalti theek karein": a bill with a mistake on it, cancelled and issued
/// again without typing it twice (M36).
///
/// A posted bill is never edited, so a wrong price used to mean cancelling
/// the bill and ringing all of it again from memory while the customer
/// waited. Now the cancel and a copy on the counter are one step, the two
/// bills name each other, and the money the customer had handed over pays
/// the corrected bill — never forgotten and never taken twice. Every test
/// drives the real screens against a real database and reads the books
/// back.
void main() {
  testWidgets(
    'a cash bill put right is cancelled, its copy opens on the counter, and '
    'the new bill replaces it',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _sell(app, cashRupees: 300);

      await _openBill(tester);
      await _startCorrecting(tester);
      // What dropping the copy would mean, said before agreeing to it.
      expect(
        find.textContaining('Rs 300.00 gahak ko wapas dene honge'),
        findsOneWidget,
      );
      await tapText(tester, 'Galat tadaad');
      await tapButton(tester, 'Mansookh kar ke naya bill kholein');

      // On the counter, the copy, saying what it replaces.
      expect(find.text('$old ki jagah naya bill'), findsOneWidget);
      expect(find.text('Chawal Basmati'), findsOneWidget);
      expect(find.text('× 150.00'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pumpAndSettle();

      await tapButton(tester, 'Paisay lein');
      // The Rs 300 the customer gave is written in, and the bill is now
      // Rs 150: Rs 150 goes back.
      expect(find.text('300.00'), findsWidgets);
      expect(find.text('Wapsi'), findsOneWidget);
      expect(find.textContaining('$old par Rs 300.00 (Cash)'), findsOneWidget);
      await tapButton(tester, 'Save karein');

      final docs = await app.rowsOf(
        'SELECT doc_no, status, void_reason, total_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice' ORDER BY doc_no",
      );
      expect(docs.first['status'], 'void');
      expect(docs.first['void_reason'], 'Galat tadaad');
      final fresh = docs.firstWhere((d) => d['doc_no'] != old)['doc_no'];
      expect(docs.first['doc_no'], old);
      expect(docs.last['status'], 'posted');
      expect(docs.last['total_paisa'], 15000);

      final links = await app.rowsOf(
        'SELECT f.doc_no AS old, t.doc_no AS new, l.link_type FROM doc_links l '
        'JOIN documents f ON f.id = l.from_document_id '
        'JOIN documents t ON t.id = l.to_document_id',
      );
      expect(links.single, {'old': old, 'new': fresh, 'link_type': 'revises'});

      // The money: Rs 300 in, handed back by the cancel, Rs 150 in on the
      // new bill with Rs 150 change. The drawer holds Rs 150, once.
      expect(await _cash(app), 15000);
      final payments = await app.rowsOf(
        'SELECT status, amount_paisa, tendered_paisa, change_paisa '
        'FROM payments ORDER BY payment_no',
      );
      expect(payments.first['status'], 'void');
      expect(payments.last, {
        'status': 'cleared',
        'amount_paisa': 15000,
        'tendered_paisa': 30000,
        'change_paisa': 15000,
      });
      // Twelve on the shelf, two sold, two back, one sold.
      expect(
        await app.scalar<int>(
          'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
        ),
        11000,
      );

      // Each bill names the other, a tap apart.
      expect(find.text('$old ki jagah bana'), findsOneWidget);
      await tester.tap(find.text('$old ki jagah bana'));
      await tester.pumpAndSettle();
      expect(find.text('Iski jagah $fresh bana'), findsOneWidget);
    },
  );

  testWidgets(
    'a bill corrected up counts the money already taken once, and the rest '
    'is owed',
    (tester) async {
      // Rs 300 to Rashid, Rs 100 of it in cash: Rs 200 on the khata. Put
      // right to three bags, Rs 450: the Rs 100 he gave still stands
      // against it, and he owes Rs 350 — not Rs 550, not Rs 250.
      final app = await Harness.startWithShop(tester);
      final rashid = await app.seedParty(name: 'Rashid Traders');
      await _sell(app, cashRupees: 100, partyId: rashid);
      expect(await _owed(app, rashid), 20000);

      await _openBill(tester);
      await _startCorrecting(tester);
      expect(
        find.textContaining('Is bill par Rs 100.00 (Cash) liye gaye the'),
        findsOneWidget,
      );
      await tapText(tester, 'Galat tadaad');
      await tapButton(tester, 'Mansookh kar ke naya bill kholein');
      expect(find.text('Rashid Traders ka bill'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tapButton(tester, 'Paisay lein');
      expect(find.text('Baqi'), findsOneWidget);
      await tapButton(tester, 'Save karein');

      expect(await _owed(app, rashid), 35000);
      expect(await _cash(app), 10000);
      final live = await app.rowsOf(
        'SELECT total_paisa, paid_paisa, balance_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice' AND status = 'posted'",
      );
      expect(live.single, {
        'total_paisa': 45000,
        'paid_paisa': 10000,
        'balance_paisa': 35000,
      });
    },
  );

  testWidgets(
    'a bill that was all on udhaar opens on udhaar, and the khata holds the '
    'corrected bill alone',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await app.seedParty(name: 'Rashid Traders');
      final old = await _sell(app, cashRupees: 0, partyId: rashid);

      await _openBill(tester);
      await _startCorrecting(tester);
      expect(
        find.text('Yeh bill udhaar par tha; naya bill bhi udhaar par khulega.'),
        findsOneWidget,
      );
      await tapText(tester, 'Galat qeemat');
      await tapButton(tester, 'Mansookh kar ke naya bill kholein');
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Paisay lein');
      final udhaar = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile).first,
      );
      expect(udhaar.value, isTrue, reason: 'it opened as a cash sale');
      expect(find.text('$old poora udhaar par tha.'), findsOneWidget);
      await tapButton(tester, 'Save karein');

      expect(await _owed(app, rashid), 15000);
      expect(await _cash(app), 0);
    },
  );

  testWidgets(
    'a bill with a receipt against it is refused in its own words, and '
    'nothing is cancelled or put on the counter',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await app.seedParty(name: 'Rashid Traders');
      await _sell(app, cashRupees: 0, partyId: rashid);
      final firm = app.services.identity!.firmId;
      final receipt = await app.services.recordReceipt(
        app.services.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(100),
          mode: 'cash',
          paymentAccountId: (await app.services.queries.paymentAccounts(
            firm,
          )).firstWhere((a) => a.isDefault).id,
        ),
      );

      await _openBill(tester);
      await _startCorrecting(tester);
      await tapText(tester, 'Galat cheez');
      await tapButton(tester, 'Mansookh kar ke naya bill kholein');

      expect(find.textContaining(receipt.paymentNo), findsOneWidget);
      expect(
        await app.scalar<String>('SELECT status FROM documents'),
        'posted',
      );
      final cart = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      ).read(cartProvider);
      expect(cart.isEmpty, isTrue, reason: 'a copy went onto the counter');
    },
  );

  testWidgets(
    'dropping the corrected copy leaves the bill cancelled and its money '
    'handed back, as the sheet said',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _sell(app, cashRupees: 300);

      await _openBill(tester);
      await _startCorrecting(tester);
      await typeInto(tester, 'Wajah', 'Gahak ne kaha theek karo');
      await tapButton(tester, 'Mansookh kar ke naya bill kholein');

      await tester.tap(find.byTooltip('Bill khali karein'));
      await tester.pumpAndSettle();
      expect(
        find.text('Naya bill chhor dein? $old phir bhi mansookh rahega.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Haan'));
      await tester.pumpAndSettle();

      expect(await app.scalar<String>('SELECT status FROM documents'), 'void');
      expect(
        await app.scalar<String>('SELECT void_reason FROM documents'),
        'Gahak ne kaha theek karo',
      );
      expect(await _cash(app), 0);
      expect(await app.countIn('doc_links'), 0);
    },
  );

  testWidgets(
    'a cashier may ring a bill again but not put one right; the owner may do '
    'both',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await _sell(app, cashRupees: 300);

      await _openBill(tester);
      await tester.tap(find.byTooltip('Aur'));
      await tester.pumpAndSettle();
      expect(find.text('Isi tarah ka naya bill'), findsOneWidget);
      expect(find.text('Ghalti theek karein'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _signInCashier(tester, app);
      await _openBill(tester);
      await tester.tap(find.byTooltip('Aur'));
      await tester.pumpAndSettle();
      expect(find.text('Isi tarah ka naya bill'), findsOneWidget);
      expect(find.text('Ghalti theek karein'), findsNothing);
    },
  );

  group('the books', () {
    late AppServices shop;
    late String firm;
    late String pcs;
    late String cash;
    late String rice;

    setUp(() async {
      shop = await openInMemoryServices();
      await shop.setUpShop(
        shopName: 'Chishti Kiryana Store',
        ownerName: 'Malik Sahib',
        deviceLabel: 'Counter 1',
      );
      firm = shop.identity!.firmId;
      pcs = (await shop.queries.units(
        firm,
      )).firstWhere((u) => u.code == 'pcs').id;
      cash = (await shop.queries.paymentAccounts(
        firm,
      )).firstWhere((a) => a.modeLabel == 'cash').id;
      rice = await shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: 'Chawal Basmati',
          baseUnitId: pcs,
          saleRate: Rate.rupees(150),
          openingStock: Qty.units(12),
          openingRate: Rate.rupees(90),
        ),
      );
    });

    tearDown(() => shop.close());

    SaleDraft bill({
      int qty = 2,
      int paid = 300,
      String? replaces,
      String? partyId,
    }) => SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: rice,
          itemName: 'Chawal Basmati',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: [
        if (paid > 0)
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: Money.rupees(paid),
          ),
      ],
      replacesId: replaces,
      partyId: partyId,
    );

    test('a bill still standing cannot be replaced', () async {
      final first = await shop.postSale(shop.actorNow(), bill());
      await expectLater(
        shop.postSale(shop.actorNow(), bill(replaces: first.documentId)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('still standing'),
          ),
        ),
      );
      expect(await _count(shop, 'documents'), 1);
    });

    test('a cancelled bill is replaced once, not twice', () async {
      final first = await shop.postSale(shop.actorNow(), bill());
      await shop.voidDocument(
        shop.actorNow(),
        documentId: first.documentId,
        reason: 'Galat tadaad',
      );
      final second = await shop.postSale(
        shop.actorNow(),
        bill(qty: 1, paid: 150, replaces: first.documentId),
      );
      await expectLater(
        shop.postSale(
          shop.actorNow(),
          bill(qty: 1, paid: 150, replaces: first.documentId),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already been put right as ${second.docNo}'),
          ),
        ),
      );
      final links = await shop.queries.billLinks(firm, first.documentId);
      expect(links.replacedBy?.docNo, second.docNo);
      final back = await shop.queries.billLinks(firm, second.documentId);
      expect(back.replaces?.docNo, first.docNo);
      // Once its replacement is itself cancelled, the bill can be put right
      // again: a correction of a correction.
      await shop.voidDocument(
        shop.actorNow(),
        documentId: second.documentId,
        reason: 'Phir ghalti',
      );
      await shop.postSale(
        shop.actorNow(),
        bill(qty: 1, paid: 150, replaces: first.documentId),
      );
    });

    test('the copy carries the money the bill took, and nothing a receipt '
        'took', () async {
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      final first = await shop.postSale(
        shop.actorNow(),
        bill(paid: 100, partyId: rashid),
      );
      // Rs 50 more against the khata later: the customer's money, but not
      // money taken with this bill (and a bill with it cannot be cancelled).
      await shop.recordReceipt(
        shop.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(50),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      final copy = (await shop.queries.billCopy(firm, first.documentId))!;
      expect(copy.paidBefore.amount, const Money.rupees(100));
      expect(copy.paidBefore.mode, 'cash');
      expect(copy.partyId, rashid);
      expect(copy.lines.single.qty, Qty.units(2));
      expect(copy.lines.single.rate, Rate.rupees(150));
    });

    test('goods already brought back stop a cancel, so a return is never '
        'counted twice', () async {
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      final first = await shop.postSale(
        shop.actorNow(),
        bill(paid: 0, partyId: rashid),
      );
      final line = await shop.database
          .customSelect('SELECT id FROM document_lines')
          .getSingle();
      final returned = await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: first.documentId,
          lines: [
            ReturnLineDraft(
              documentLineId: line.read<String>('id'),
              qty: Qty.one,
            ),
          ],
          reason: 'Toota hua',
        ),
      );
      await expectLater(
        shop.voidDocument(
          shop.actorNow(),
          documentId: first.documentId,
          reason: 'Ghalti',
        ),
        throwsA(
          isA<VoidRefused>().having(
            (r) => r.reason,
            'reason',
            contains(returned.docNo),
          ),
        ),
      );
      expect(
        (await shop.database
                .customSelect(
                  "SELECT status FROM documents WHERE id = '${first.documentId}'",
                )
                .getSingle())
            .read<String>('status'),
        'posted',
      );
    });

    test('a cheque taken at the counter that has gone to the bank stops a '
        'cancel', () async {
      await shop.plans.setTestPlan(Plan.platinum);
      final party = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      final cheque = (await shop.queries.paymentAccounts(
        firm,
      )).firstWhere((a) => a.modeLabel == 'cheque').id;
      final sale = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          partyId: party,
          lines: bill().lines,
          tenders: [
            TenderDraft(
              paymentAccountId: cheque,
              mode: 'cheque',
              amount: const Money.rupees(300),
              chequeNo: '000777',
              chequeBank: 'Meezan',
              chequeDateUtc: DateTime.utc(2026, 10, 3),
            ),
          ],
        ),
      );
      await shop.cheques.deposit(shop.actorNow(), sale.paymentIds.single);
      await expectLater(
        shop.voidDocument(
          shop.actorNow(),
          documentId: sale.documentId,
          reason: 'Ghalti',
        ),
        throwsA(
          isA<VoidRefused>().having(
            (r) => r.reason,
            'reason',
            contains('000777'),
          ),
        ),
      );
    });

    test(
      'a cheque still in the shop goes with its bill, as cash does',
      () async {
        await shop.plans.setTestPlan(Plan.platinum);
        final party = await shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Rashid Traders'),
        );
        final cheque = (await shop.queries.paymentAccounts(
          firm,
        )).firstWhere((a) => a.modeLabel == 'cheque').id;
        final sale = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            partyId: party,
            lines: bill().lines,
            tenders: [
              TenderDraft(
                paymentAccountId: cheque,
                mode: 'cheque',
                amount: const Money.rupees(300),
                chequeNo: '000778',
                chequeBank: 'Meezan',
                chequeDateUtc: DateTime.utc(2026, 10, 3),
              ),
            ],
          ),
        );
        final copy = (await shop.queries.billCopy(firm, sale.documentId))!;
        expect(copy.paidBefore.mode, 'cheque');
        expect(copy.paidBefore.chequeNo, '000778');
        await shop.voidDocument(
          shop.actorNow(),
          documentId: sale.documentId,
          reason: 'Ghalti',
        );
      },
    );
  });
}

Future<int> _count(AppServices shop, String table) async =>
    (await shop.database
            .customSelect('SELECT COUNT(*) AS c FROM $table')
            .getSingle())
        .read<int>('c');

/// What the shop's cash account holds, in paisa, by the journal.
Future<int> _cash(Harness app) async =>
    await app.scalar<int>(
      'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
      'FROM journal_lines jl WHERE jl.deleted_at_utc IS NULL '
      'AND jl.account_id = (SELECT ledger_account_id FROM payment_accounts '
      "WHERE mode_label = 'cash' LIMIT 1)",
    ) ??
    0;

/// What [partyId] owes the shop, in paisa, as the khata says it.
Future<int> _owed(Harness app, String partyId) async =>
    (await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    ))!.balance.inPaisa;

Future<void> _openBill(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('INV-').first);
  await tester.pumpAndSettle();
}

Future<void> _startCorrecting(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Aur'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ghalti theek karein').last);
  await tester.pumpAndSettle();
}

/// Two bags of rice at Rs 150 off a shelf of twelve, [cashRupees] of it in
/// cash, to [partyId] or a walk-in. Returns the bill's number.
Future<String> _sell(
  Harness app, {
  required int cashRupees,
  String? partyId,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final rice = await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Chawal Basmati',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(150),
      openingStock: Qty.units(12),
      openingRate: Rate.rupees(90),
    ),
  );
  final sale = await app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: rice,
          itemName: 'Chawal Basmati',
          qty: Qty.units(2),
          baseQty: Qty.units(2),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: [
        if (cashRupees > 0)
          TenderDraft(
            paymentAccountId: (await app.services.queries.paymentAccounts(
              firm,
            )).firstWhere((a) => a.isDefault).id,
            mode: 'cash',
            amount: Money.rupees(cashRupees),
          ),
      ],
    ),
  );
  return sale.docNo;
}

/// The owner's PIN, a cashier hired, and the cashier signed in.
Future<void> _signInCashier(WidgetTester tester, Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Bilal · Cashier');
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
  expect(services.currentUser?.role, Role.cashier);
}
