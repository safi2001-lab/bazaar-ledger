import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/attachments/attachment_strip.dart';
import 'package:bazaar_ledger/features/batches/stock_places_screen.dart';
import 'package:bazaar_ledger/features/cheques/cheques_screen.dart';
import 'package:bazaar_ledger/features/import/import_screen.dart';
import 'package:bazaar_ledger/features/loans/loan_screen.dart';
import 'package:bazaar_ledger/features/sales/send_bill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// The polish round away from the counter (M54): Home, a bill's history,
/// the pharmacy's challan and delivery, papers on more entries, and the
/// recovery man's cheque — each through the screens a shopkeeper uses, on
/// a real database.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);

  testWidgets('a bill sent from its row is written on its history, and a '
      'bill shared before is not sent as a duplicate', (tester) async {
    final app = await Harness.startWithShop(tester);
    final bill = await _sellCheeni(app);

    await tester.pumpAndSettle();
    await tapText(tester, 'Farokht');
    await tester.tap(find.byTooltip('Bhejein'));
    await tester.pumpAndSettle();
    // A walk-in has no number, so WhatsApp goes as a PDF through the sheet.
    await tester.tap(find.text('WhatsApp par bhejein'));
    await _settleWhileBusy(tester);
    expect(_sheet.paths.single, endsWith('${bill.docNo}.pdf'));
    expect(
      await app.scalar<String>(
        "SELECT action_code FROM audit_log WHERE action_code LIKE 'SHARED_%'",
      ),
      'SHARED_PDF',
    );

    // Sent once, it is still the original: DUPLICATE is for paper.
    final again = await tester.runAsync(
      () => OutgoingDocument.load(app.services, bill.documentId),
    );
    expect(again!.receipt.isReprint, isFalse);

    await tapText(tester, bill.docNo);
    await tester.tap(find.byTooltip('Tareekh'));
    await tester.pumpAndSettle();
    expect(find.text('PDF bheji'), findsOneWidget);
    expect(find.textContaining('Malik Sahib'), findsWidgets);
  });

  testWidgets('a Schedule medicine sent on a challan asks for the '
      'prescription there, and the bill made from it carries it', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.services.updateFirm({'business_kind': 'pharmacy'});
    await _refresh(tester);
    await _medicine(app, 'Xanax 0.5', schedule: ScheduleClass.b, onHand: 20);
    await app.seedParty(name: 'Shifa Clinic');

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Xanax',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Paisay lein');
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Shifa Clinic');
    await tapButton(tester, 'Challan banayein');

    expect(find.text('DOCTOR KA NUSKHA'), findsOneWidget);
    await typeInto(tester, 'Mareez ka naam', 'Bilal Ahmed');
    await typeInto(tester, 'Doctor ka naam', 'Dr Ayesha Khan');
    await typeInto(tester, 'Doctor ka PM&DC registration no.', '12345-P');
    await tapButton(tester, 'Aage barhein');
    await tester.pumpAndSettle();

    // The register line is the strip that left, on the challan.
    final registered = await app.rowsOf(
      'SELECT d.doc_type, rx.patient_name FROM stock_ledger s '
      'JOIN prescriptions rx ON rx.document_line_id = s.document_line_id '
      'JOIN documents d ON d.id = s.document_id',
    );
    expect(registered, [
      {'doc_type': 'delivery_challan', 'patient_name': 'Bilal Ahmed'},
    ]);

    // From the counter back home, to the challans.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Challan');
    await tapText(tester, 'Shifa Clinic');
    await tapButton(tester, 'Is se bill banayein');
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    expect(find.text('DOCTOR KA NUSKHA'), findsNothing, reason: 'asked once');
    expect(
      await app.rowsOf(
        'SELECT rx.patient_name FROM prescriptions rx '
        'JOIN documents d ON d.id = rx.document_id '
        "WHERE d.doc_type = 'sale_invoice'",
      ),
      [
        {'patient_name': 'Bilal Ahmed'},
      ],
    );
  });

  testWidgets("a purchase order's delivery asks each batch its printed "
      'price, as the delivery picker does', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    final panadol = await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Panadol 500',
        baseUnitId: pcs.id,
        saleRate: const Rate.rupees(50),
        mrp: const Money.rupees(50),
        tracksBatch: true,
      ),
    );
    final agency = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Muller Pharma', partyType: 'supplier'),
    );
    await services.orders.place(
      OrderDraft(
        kind: OrderKind.purchase,
        partyId: agency,
        lines: [
          OrderLineDraft(
            itemId: panadol,
            itemName: 'Panadol 500',
            qty: Qty.units(100),
            baseQty: Qty.units(100),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: const Rate.rupees(35),
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Order');
    await tapText(tester, 'Purchase order (PO)');
    await tapText(tester, 'Muller Pharma');
    await tapButton(tester, 'Maal aa gaya');
    await tapText(tester, 'Panadol 500');
    // Starts at the item's own printed price.
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'MRP fi pcs'),
          )
          .controller!
          .text,
      '50.00',
    );
    await typeInto(tester, 'Batch no.', 'PN-2611');
    await typeInto(tester, 'Expiry', '2027-06-30');
    await typeInto(tester, 'MRP fi pcs', '55');
    await tapButton(tester, 'Save karein');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Kharidari save karein');

    expect(
      await app.rowsOf(
        "SELECT lot_no, mrp_paisa FROM stock_lots WHERE lot_no = 'PN-2611'",
      ),
      [
        {'lot_no': 'PN-2611', 'mrp_paisa': 5500},
      ],
    );
  });

  testWidgets("a Vyapar item list's second unit comes in as the item's pack, "
      'and a Generic column as the salt', (tester) async {
    const csv =
        'Item Name*,Sale Price,Base Unit (x),Secondary Unit (y),'
        'Conversion Rate (n) (x = ny),Opening Stock Quantity,Generic\n'
        'Gala Biscuit,40,PCS,CARTON,24,53,\n'
        'Basmati Rice,300,Kg,BAG,25,50,\n'
        'Lux Soap,100,PCS,BOX,2.5,10,\n'
        'Panadol 500,2,Pcs,,,100,Paracetamol\n';
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        pickImportFileProvider.overrideWithValue(
          () async => ('items.csv', Uint8List.fromList(utf8.encode(csv))),
        ),
      ],
    );
    await openSettings(tester);
    await tapText(tester, 'Excel se laayein');
    await tapButton(tester, 'File chunein');

    expect(
      find.text('1 cheezen pack ke saath aayengi: 1 carton = 24 pcs'),
      findsOneWidget,
    );
    expect(
      find.text('1 cheezen pack ke saath aayengi: 1 bori = 25 kg'),
      findsOneWidget,
    );
    // Not whole: as M52 brought it, by its first unit, and said.
    expect(find.textContaining('doosra unit hai (1 pcs = 2.5 BOX)'), findsOne);

    await tapButton(tester, '4 laayein');

    final packs = await app.rowsOf(
      'SELECT i.name, f.code AS pack, t.code AS unit, c.factor_thousandths f '
      'FROM unit_conversions c JOIN items i ON i.id = c.item_id '
      'JOIN units f ON f.id = c.from_unit_id '
      'JOIN units t ON t.id = c.to_unit_id '
      'WHERE c.deleted_at_utc IS NULL ORDER BY i.name',
    );
    expect(packs, [
      {'name': 'Basmati Rice', 'pack': 'bori', 'unit': 'kg', 'f': 25000},
      {'name': 'Gala Biscuit', 'pack': 'carton', 'unit': 'pcs', 'f': 24000},
    ]);
    expect(
      await app.scalar<int>(
        'SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s '
        "JOIN items i ON i.id = s.item_id WHERE i.name = 'Gala Biscuit'",
      ),
      53000,
      reason: 'the shelf as the sheet counted it, in pieces',
    );
    expect(
      await app.scalar<String>(
        "SELECT generic_name FROM items WHERE name = 'Panadol 500'",
      ),
      'Paracetamol',
    );
  });

  testWidgets("a loan's entries, a cheque's own page and a batch each carry "
      'the strip of photographs', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firmId = services.identity!.firmId;
    final accounts = await services.queries.paymentAccounts(firmId);
    String account(String mode) =>
        accounts.firstWhere((a) => a.modeLabel == mode).id;

    final loan = await services.loans.take(
      LoanDraft(
        lender: 'Meezan Bank',
        amount: const Money.rupees(500000),
        intoPaymentAccountId: account('bank_transfer'),
        takenOn: BusinessDate.now(services.clock),
      ),
    );
    final entry = (await services.loans.statement(loan)).lines.single;

    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 5000,
    );
    final cheque = await services.recordReceipt(
      services.actorNow(),
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(5000),
        mode: 'cheque',
        paymentAccountId: account('cheque'),
        chequeNo: '000451',
        chequeBank: 'HBL',
        chequeDateUtcMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
    );

    final pcs = (await services.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    final panadol = await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Panadol 500',
        baseUnitId: pcs.id,
        saleRate: const Rate.rupees(2),
        tracksBatch: true,
      ),
    );
    final muller = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Muller Pharma', partyType: 'supplier'),
    );
    await services.recordPurchase(
      services.actorNow(),
      PurchaseDraft(
        partyId: muller,
        lines: [
          PurchaseLineDraft(
            itemId: panadol,
            itemName: 'Panadol 500',
            qty: Qty.units(100),
            baseQty: Qty.units(100),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: const Rate.rupees(1),
            batchNo: 'PN-2611',
            expiry: const BusinessDate('2027-06-30'),
          ),
        ],
      ),
    );
    final lot = (await services.queries.lotsOnHand(
      firmId,
      itemId: panadol,
    )).single;
    final item = (await services.queries.itemById(firmId, panadol))!;

    Future<void> open(Widget screen) async {
      unawaited(
        Navigator.of(
          tester.element(find.byType(Scaffold).first),
        ).push(MaterialPageRoute<void>(builder: (_) => screen)),
      );
      await tester.pumpAndSettle();
    }

    AttachmentOwner strip() =>
        tester.widget<AttachmentStrip>(find.byType(AttachmentStrip)).owner;

    // A list of entries or of batches carries M60's button on each, which
    // opens the strip; a cheque's own page carries the strip itself.
    Future<void> photosOf(AttachmentOwner owner) async {
      expect(
        tester.widget<EntryPhotosButton>(find.byType(EntryPhotosButton)).owner,
        owner,
      );
      await tester.tap(find.byType(EntryPhotosButton));
      await tester.pumpAndSettle();
      expect(strip(), owner);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    await open(LoanScreen(loanId: loan));
    await photosOf(AttachmentOwner.loanEntry(entry.entryId));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await open(const ChequesScreen());
    await tapText(tester, 'Rashid Traders');
    expect(strip(), AttachmentOwner.payment(cheque.paymentId, cheque: true));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await open(StockPlacesScreen(item: item));
    await photosOf(AttachmentOwner.batch(lot.lotId));
  });

  testWidgets("the recovery man's cheque is written on his round's line, "
      'and becomes a cheque receipt with the rest of the round', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    Future<String> owing(String name, int rupees) =>
        app.services.catalogue.addParty(
          app.services.actorNow(),
          PartyDraft(name: name, openingBalance: Money.rupees(rupees)),
        );
    final aslam = await owing('Aslam Karyana', 5000);
    await owing('Bilal Store', 3000);
    final sheet = await app.services.collections.makeSheet(
      SheetDraft(
        partyIds: [
          aslam,
          (await app.services.queries.searchParties(
            app.services.identity!.firmId,
            query: 'Bilal',
          )).single.id,
        ],
        collector: 'Rafiq',
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tester.tap(find.byTooltip('Udhaar wasooli'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Wasooli sheets'));
    await tester.pumpAndSettle();
    await tapText(tester, '${sheet.sheetNo} · Rafiq');
    await tapButton(tester, 'Wapsi par likhein');
    await _tapIn(tester, 'Aslam Karyana', find.text('Pura diya'));
    await _tapIn(tester, 'Aslam Karyana', find.text('Cheque'));
    await _save(tester);
    expect(
      find.text('Aslam Karyana: cheque ka number likhein'),
      findsOneWidget,
    );

    await tester.enterText(
      _in('Aslam Karyana', find.widgetWithText(TextFormField, 'Cheque number')),
      '000451',
    );
    await tester.enterText(
      _in('Aslam Karyana', find.widgetWithText(TextFormField, 'Bank ka naam')),
      'HBL',
    );
    await tester.pumpAndSettle();
    await _tapIn(tester, 'Bilal Store', find.text('Pura diya'));
    await _save(tester);
    await settleReal(
      tester,
      until: find.text('Wasooli likh li: Rs 8,000.00 aaye'),
    );

    final cheques = await app.rowsOf(
      'SELECT cheque_no, cheque_bank, status, amount_paisa FROM payments '
      "WHERE mode = 'cheque'",
    );
    expect(cheques, [
      {
        'cheque_no': '000451',
        'cheque_bank': 'HBL',
        'status': 'pending',
        'amount_paisa': 500000,
      },
    ]);
  });

  testWidgets('the monthly bills whose day has come are one line on Home, '
      'and it opens the Expenses screen with each to pay', (tester) async {
    final app = await Harness.startWithShop(tester);
    final money = app.services.shopMoney;
    await money.saveMonthlyBill(
      MonthlyBill(
        id: money.newMonthlyBillId(),
        headKey: 'rent',
        amount: const Money.rupees(40000),
        note: 'Haji Sahib ka kiraya',
        day: 1,
      ),
    );
    await money.saveMonthlyBill(
      MonthlyBill(
        id: money.newMonthlyBillId(),
        headKey: 'utilities',
        amount: const Money.rupees(9000),
        note: 'LESCO bill',
        day: 1,
      ),
    );
    await _refresh(tester);

    final line = find.textContaining('Mahana bill: 2 baqi, Rs 49,000.00');
    expect(line, findsOneWidget);
    expect(find.textContaining('Haji Sahib ka kiraya'), findsOneWidget);
    expect(find.textContaining('LESCO bill'), findsOneWidget);

    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(
      find.text('Is mahine dena hai: Haji Sahib ka kiraya'),
      findsOneWidget,
    );
    expect(await app.countIn('documents'), 0, reason: 'nothing paid by itself');
  });

  testWidgets('no line on Home when no monthly bill is due', (tester) async {
    await Harness.startWithShop(tester);
    expect(find.textContaining('Mahana bill'), findsNothing);
  });
}

/// A medicine on the shelf, of [schedule] when given.
Future<String> _medicine(
  Harness app,
  String name, {
  ScheduleClass? schedule,
  int onHand = 0,
}) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final pcs = (await services.queries.units(
    firm.id,
  )).firstWhere((u) => u.code == 'pcs');
  return services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs.id,
      saleRate: const Rate.rupees(40),
      openingStock: Qty.units(onHand),
      openingRate: const Rate.rupees(20),
      medicine: MedicineDetails(
        genericName: 'Alprazolam',
        strength: '0.5 mg',
        schedule: schedule,
      ),
    ),
  );
}

/// Rs 300 of cheeni to a walk-in, paid in cash.
Future<PostedSale> _sellCheeni(Harness app) async {
  final firm = app.services.identity!.firmId;
  final itemId = await app.seedItem(name: 'Cheeni', rupees: 300);
  final item = (await app.services.queries.itemById(firm, itemId))!;
  final cash = (await app.services.queries.paymentAccounts(
    firm,
  )).firstWhere((a) => a.modeLabel == 'cash');
  return app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cheeni',
          qty: Qty.one,
          baseQty: Qty.one,
          unitId: item.unitId,
          unitCode: item.unitCode,
          rate: const Rate.rupees(300),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(300),
        ),
      ],
    ),
  );
}

/// Lets a PDF render and a share sheet answer: real file IO under a fake
/// clock.
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// The round's save, scrolled to: the cheque's fields push it below the
/// part of the list that is built.
Future<void> _save(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.textContaining('Sab khaton par likhein'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tapButton(tester, 'Sab khaton par likhein');
}

/// [finder] inside the card for [name].
Finder _in(String name, Finder finder) => find.descendant(
  of: find
      .ancestor(of: find.textContaining(name), matching: find.byType(BlCard))
      .first,
  matching: finder,
);

Future<void> _tapIn(WidgetTester tester, String name, Finder finder) async {
  final target = _in(name, finder).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Tells every list the books moved, as a save on a screen would.
Future<void> _refresh(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}
