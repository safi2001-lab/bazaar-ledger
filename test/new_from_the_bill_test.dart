import 'package:bazaar_ledger/app/preferences.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// A new customer or a new item, added from the bill without leaving it (M32).
///
/// Shopkeepers trying the app said it plainly: "in Vyapar, when we make a
/// bill and the product or the person is new, it gets added automatically."
/// Here a cashier had to abandon the bill, go to Customers or Items, add the
/// record, come back and find the bill again — with a customer waiting.
///
/// Every test drives the real screens against a real database and then reads
/// the rows back: the party or item that was made, the bill it went on, the
/// stock it moved and the books it reached.
void main() {
  testWidgets(
    'a new customer typed on the bill is made, chosen, and the bill is on '
    'their khata',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

      await _ringUpAndPay(tester, 'Cooking');
      await _newCustomer(tester, 'Rashid Raza');

      // The name came with it; the mobile is typed however they say it.
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Naam').last,
            )
            .controller!
            .text,
        'Rashid Raza',
      );
      await _typeOnTop(tester, 'Mobile (marzi se)', '0300-4471203');
      await _tapOnTop(tester, 'Save karein');

      // Back on the payment sheet with them on the bill, and the bill goes
      // on their khata.
      expect(find.text('Rashid Raza'), findsOneWidget);
      await _onUdhaar(tester);

      final party = (await app.rowsOf(
        'SELECT id, phone, party_type, price_tier FROM parties',
      )).single;
      expect(
        party['phone'],
        '0300 4471203',
        reason: 'kept the way every reminder can reach it',
      );
      expect(party['party_type'], 'customer');
      expect(party['price_tier'], 'retail');

      final bill = (await app.rowsOf(
        "SELECT party_id, total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
      )).single;
      expect(bill['party_id'], party['id']);
      final khata = await app.services.queries.partyById(
        app.services.identity!.firmId,
        party['id']! as String,
      );
      expect(khata!.balance, const Money.rupees(2500));
    },
  );

  testWidgets('a new customer put on wholesale is charged wholesale at once', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _oilWithTradePrice(app);

    await _ringUpAndPay(tester, 'Cooking');
    await _newCustomer(tester, 'Rashid Traders');
    await tapText(tester, 'Thok (wholesale)');
    await _tapOnTop(tester, 'Save karein');
    await _onUdhaar(tester);

    expect(
      await app.scalar<int>(
        "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      230000,
      reason: 'the lines did not follow the new customer to the trade price',
    );
    expect(await app.scalar<String>('SELECT price_tier FROM parties'), 'wholesale');
  });

  testWidgets(
    'someone already in the khata by their mobile is offered, not added twice',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
      final rashid = await app.seedParty(
        name: 'Rashid Traders',
        phone: '+92 300 4471203',
      );

      await _ringUpAndPay(tester, 'Cooking');
      await _newCustomer(tester, 'R. Raza');
      // The same phone, written the way the counter boy heard it.
      await _typeOnTop(tester, 'Mobile (marzi se)', '0300-4471203');
      await _tapOnTop(tester, 'Save karein');

      expect(find.text('Yeh pehle se khata mein hain'), findsOneWidget);
      await tapText(tester, 'Rashid Traders · +92 300 4471203');

      expect(find.text('Rashid Traders'), findsOneWidget);
      await _onUdhaar(tester);

      expect(await app.countIn('parties'), 1, reason: 'a second khata opened');
      expect(
        await app.scalar<String>(
          "SELECT party_id FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        rashid,
      );
    },
  );

  testWidgets('the same name twice is warned about, and added on purpose', (
    tester,
  ) async {
    // Two Ali Razas in one mohalla is ordinary. Being told is the point;
    // being stopped is not.
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    final first = await app.seedParty(name: 'Ali Raza');

    await _ringUpAndPay(tester, 'Cooking');
    // "Ali R" finds "Ali Raza" and is not him, so the offer still stands.
    await _newCustomer(tester, 'Ali R');
    await _typeOnTop(tester, 'Naam', 'ali  raza');
    await _tapOnTop(tester, 'Save karein');

    expect(find.text('Yeh pehle se khata mein hain'), findsOneWidget);
    await _tapOnTop(tester, 'Nahi, naya banayein');
    await _onUdhaar(tester);

    expect(await app.countIn('parties'), 2);
    final billed = await app.scalar<String>(
      "SELECT party_id FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(billed, isNot(first), reason: 'the bill went to the namesake');
  });

  testWidgets('a new item typed on the bill is made, sold, and its stock moves', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openCounter(tester);

    await _search(tester, 'Surf Excel 1kg');
    expect(find.text('Kuch nahi mila'), findsOneWidget);
    await tapText(tester, "'Surf Excel 1kg' ko naya maal banayein");

    await _typeOnTop(tester, 'Farokht ki qeemat', '350');
    await _typeOnTop(tester, 'Khareed ki qeemat', '300');
    await _typeOnTop(tester, 'Mojooda stock', '10');
    await _tapOnTop(tester, 'Save karein');

    // On the bill, one of it, without searching again.
    expect(find.text('Surf Excel 1kg'), findsOneWidget);
    expect(find.text('1 pcs'), findsOneWidget);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '350');
    await tapButton(tester, 'Save karein');

    final item = (await app.rowsOf(
      'SELECT id, sale_rate_milli_paisa s, purchase_rate_milli_paisa p, '
      'avg_cost_milli_paisa a FROM items',
    )).single;
    expect(item['s'], const Rate.rupees(350).inMilliPaisa);
    expect(item['p'], const Rate.rupees(300).inMilliPaisa);
    expect(item['a'], const Rate.rupees(300).inMilliPaisa);

    // Ten on the shelf as an opening row, one gone with the bill.
    final moves = await app.rowsOf(
      'SELECT txn_type, qty_delta_thousandths q FROM stock_ledger '
      'ORDER BY occurred_at_utc, txn_type',
    );
    expect(moves.map((m) => (m['txn_type'], m['q'])), [
      ('opening', 10000),
      ('sale', -1000),
    ]);

    // And the books: Rs 3,000 of goods opened at cost, Rs 300 of them sold.
    expect(
      await app.scalar<int>(
        'SELECT SUM(jl.debit_paisa - jl.credit_paisa) FROM journal_lines jl '
        'JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key = 'inventory'",
      ),
      270000,
    );
  });

  testWidgets('a new item on the bill survives the app being killed', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openCounter(tester);

    await _search(tester, 'Surf Excel 1kg');
    await tapText(tester, "'Surf Excel 1kg' ko naya maal banayein");
    await _typeOnTop(tester, 'Farokht ki qeemat', '350');
    await _tapOnTop(tester, 'Save karein');

    // Written on the mutation, like every other line: Android says nothing
    // before a force-stop.
    await tester.pump(const Duration(milliseconds: 50));
    final saved = await app.services.drafts.read(cartDraftSlot);
    final restored = CartDraft.decode(saved!)!;
    final id = await app.scalar<String>('SELECT id FROM items');
    expect(restored.lines.single.item.id, id);
    expect(restored.lines.single.item.name, 'Surf Excel 1kg');
    expect(restored.subtotal, const Money.rupees(350));
  });

  testWidgets(
    'an unknown barcode becomes an item with that barcode, and the next scan '
    'finds it',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await _openCounter(tester);

      await _scan(tester, '8964000555555');
      await tapText(tester, 'Barcode 8964000555555 se naya maal banayein');

      // The digits go in as the barcode, never as the name.
      TextEditingController field(String label) => tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, label).last,
          )
          .controller!;
      expect(field('Barcode (marzi se)').text, '8964000555555');
      expect(field('Naam').text, isEmpty);
      await _typeOnTop(tester, 'Naam', 'Tapal Danedar 190g');
      await _typeOnTop(tester, 'Farokht ki qeemat', '450');
      await _tapOnTop(tester, 'Save karein');

      expect(find.text('Tapal Danedar 190g'), findsOneWidget);
      expect(find.text('1 pcs'), findsOneWidget);

      await _scan(tester, '8964000555555');
      expect(find.text('2 pcs'), findsOneWidget);
      expect(
        await app.scalar<String>('SELECT barcode FROM items'),
        '8964000555555',
      );
    },
  );

  testWidgets(
    'a scale label nobody coded becomes an item and rings up its weight',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await _openCounter(tester);

      await _scan(tester, _label('21', '00077', '01500'));
      expect(
        find.text('Scale label par PLU 77 kisi maal ka code nahin'),
        findsOneWidget,
      );
      await tapText(tester, 'Code 77 se naya maal banayein');

      expect(find.widgetWithText(TextFormField, '77'), findsOneWidget);
      await _typeOnTop(tester, 'Naam', 'Qeema');
      await _typeOnTop(tester, 'Farokht ki qeemat', '1000');
      await _tapOnTop(tester, 'Save karein');

      // Made with nothing on the shelf, so the counter asks before the
      // weight goes on the bill (M53), and the cashier says sell.
      expect(find.text('Stock sirf 0 kg hai — phir bhi bechein?'), findsOne);
      await tester.tap(find.text('Haan, bechein'));
      await tester.pumpAndSettle();

      expect(find.text('Qeema'), findsOneWidget);
      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '1500');
      await tapButton(tester, 'Save karein');

      final item = (await app.rowsOf(
        'SELECT i.code, u.code AS unit FROM items i '
        'JOIN units u ON u.id = i.base_unit_id',
      )).single;
      expect(item['code'], '77', reason: 'the next label would miss again');
      expect(item['unit'], 'kg', reason: 'mutton is not sold in pieces');
      expect(
        await app.scalar<int>('SELECT qty_thousandths FROM document_lines'),
        1500,
        reason: 'the label said 1.500 kg',
      );
    },
  );

  testWidgets('an item already in the shop is offered instead of a twin', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Chawal Basmati', rupees: 525);
    await _openCounter(tester);

    await _search(tester, 'Basmati 5kg');
    await tapText(tester, "'Basmati 5kg' ko naya maal banayein");
    await _typeOnTop(tester, 'Naam', 'chawal  basmati');
    await _typeOnTop(tester, 'Farokht ki qeemat', '525');
    await _tapOnTop(tester, 'Save karein');

    expect(find.text('Yeh maal pehle se hai'), findsOneWidget);
    await tapText(tester, 'Chawal Basmati');

    expect(find.text('Chawal Basmati'), findsOneWidget);
    expect(find.text('1 pcs'), findsOneWidget);
    expect(await app.countIn('items'), 1, reason: 'a twin was made anyway');
  });

  testWidgets('a cashier is not asked what a new item cost, nor for its stock', (
    tester,
  ) async {
    // M9: a cashier cannot see what goods cost. He is not asked to type it,
    // and so not the stock either — the books value stock at its cost.
    final app = await Harness.startWithShop(tester);
    await _signInBilal(tester, app);
    await _openCounter(tester);

    await _search(tester, 'Surf Excel 1kg');
    await tapText(tester, "'Surf Excel 1kg' ko naya maal banayein");

    expect(find.widgetWithText(TextFormField, 'Khareed ki qeemat'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Mojooda stock'), findsNothing);
    expect(
      find.text(
        'Khareed ki qeemat aur stock maalik baad mein Maal se daalein ge.',
      ),
      findsOneWidget,
    );

    await _typeOnTop(tester, 'Farokht ki qeemat', '350');
    await _tapOnTop(tester, 'Save karein');
    expect(find.text('Surf Excel 1kg'), findsOneWidget);

    final item = (await app.rowsOf(
      'SELECT purchase_rate_milli_paisa p, avg_cost_milli_paisa a FROM items',
    )).single;
    expect(item['p'], isNull);
    expect(item['a'], 0);
    expect(await app.countIn('stock_ledger'), 0);
  });

  testWidgets('a cashier cannot put a new customer on trade prices', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await _signInBilal(tester, app);

    await _ringUpAndPay(tester, 'Cooking');
    await _newCustomer(tester, 'Naveed Bhai');

    expect(find.text('Kis rate par bechna hai'), findsNothing);
    expect(find.text('Thok (wholesale)'), findsNothing);

    await _tapOnTop(tester, 'Save karein');
    expect(find.text('Naveed Bhai'), findsOneWidget);
    expect(await app.scalar<String>('SELECT price_tier FROM parties'), 'retail');
  });

  testWidgets(
    'a new supplier and a new item are made on the delivery, and it moves '
    'the cost',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await tester.pumpAndSettle();
      await tapText(tester, 'Kharidari');
      await tapText(tester, 'Nayi kharidari');

      await tapText(tester, 'Supplier chunein');
      await _typeOnTop(tester, 'Talash karein', 'Faisal Flour Mills');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, "'Faisal Flour Mills' ko naya supplier banayein");
      expect(find.text('Naya supplier'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Udhaar ki hadd (marzi se)'),
        findsNothing,
        reason: 'a supplier is not given credit by the shop',
      );
      await _tapOnTop(tester, 'Save karein');
      expect(find.text('Faisal Flour Mills'), findsOneWidget);

      await tapText(tester, 'Cheez shamil karein');
      await _typeOnTop(tester, 'Talash karein', 'Atta 10kg');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, "'Atta 10kg' ko naya maal banayein");

      // On a delivery the cost is the price being bought at, and the
      // delivery is the stock: no opening stock is asked.
      expect(find.widgetWithText(TextFormField, 'Mojooda stock'), findsNothing);
      await _typeOnTop(tester, 'Farokht ki qeemat', '1100');
      await _typeOnTop(tester, 'Khareed ki qeemat (fi unit)', '950');
      await _tapOnTop(tester, 'Save karein');

      // Straight on to the line, the cost following the quantity.
      await _typeOnTop(tester, 'Tadaad (pcs)', '10');
      expect(find.widgetWithText(TextFormField, '9,500.00'), findsOneWidget);
      await tester.tap(find.text('Cheez shamil karein').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Kharidari save karein');

      expect(
        await app.scalar<String>('SELECT party_type FROM parties'),
        'supplier',
      );
      final item = (await app.rowsOf(
        'SELECT purchase_rate_milli_paisa p, avg_cost_milli_paisa a FROM items',
      )).single;
      expect(item['p'], const Rate.rupees(950).inMilliPaisa);
      expect(item['a'], const Rate.rupees(950).inMilliPaisa);
      final moves = await app.rowsOf(
        'SELECT txn_type, qty_delta_thousandths q FROM stock_ledger',
      );
      expect(moves.map((m) => (m['txn_type'], m['q'])), [('purchase', 10000)]);
      expect(
        await app.scalar<int>(
          "SELECT total_paisa FROM documents WHERE doc_type = 'purchase_bill'",
        ),
        950000,
      );
    },
  );

  testWidgets('a challan goes to a customer made from the bill', (
    tester,
  ) async {
    // Quotations and challans are kept from the same counter and the same
    // payment sheet, so they get the new customer for free.
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await _ringUpAndPay(tester, 'Cooking');
    await _newCustomer(tester, 'Haji Sahib');
    await _tapOnTop(tester, 'Save karein');
    await tapButton(tester, 'Challan banayein');

    final party = await app.scalar<String>('SELECT id FROM parties');
    final challan = (await app.rowsOf(
      'SELECT doc_type, party_id FROM documents',
    )).single;
    expect(challan['doc_type'], 'delivery_challan');
    expect(challan['party_id'], party);
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the new-item offer and sheet fit', (tester) async {
      _useASmallPhone(tester);
      await Harness.startWithShop(tester);
      await _openCounter(tester);

      await _search(tester, 'Surf Excel Washing Powder 1kg Family Pack');
      _expectNothingPaintsOffScreen(tester);
      await tapText(
        tester,
        "'Surf Excel Washing Powder 1kg Family Pack' ko naya maal banayein",
      );
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the scale label offer fits', (tester) async {
      _useASmallPhone(tester);
      await Harness.startWithShop(tester);
      await _openCounter(tester);

      await _scan(tester, _label('21', '00077', '01500'));
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the new-customer offer and sheet fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

      await _ringUpAndPay(tester, 'Cooking');
      await tapText(tester, 'Aam gahak');
      await _typeOnTop(tester, 'Talash karein', 'Chaudhry Muhammad Aslam');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, "'Chaudhry Muhammad Aslam' ko naya gahak banayein");
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('and in English', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(
        tester,
        overrides: [
          initialPreferencesProvider.overrideWithValue(
            AppPreferences(locale: const Locale('en'), themeMode: ThemeMode.light),
          ),
        ],
      );
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
      await tester.tap(find.text('New Bill').first);
      await tester.pumpAndSettle();

      await _search(tester, 'Surf Excel Washing Powder 1kg', label: 'Search');
      await tapText(
        tester,
        "Add 'Surf Excel Washing Powder 1kg' as a new item",
      );
      expect(find.text('New item'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();

      await _search(tester, 'Cooking', label: 'Search');
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Take payment');
      await tapText(tester, 'Walk-in customer');
      await _typeOnTop(tester, 'Search', 'Chaudhry Muhammad Aslam');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, "Add 'Chaudhry Muhammad Aslam' as a new customer");
      expect(find.text('Mobile (optional)'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

// ---------------------------------------------------------------------------

Future<void> _openCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.pumpAndSettle();
}

/// Types in the counter's search and waits out its debounce.
Future<void> _search(
  WidgetTester tester,
  String text, {
  String label = 'Talash karein',
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, label).first, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// A wedge scanner: fast typing, then Enter.
Future<void> _scan(WidgetTester tester, String code) async {
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// Rings up the first match for [query] and opens the payment sheet.
Future<void> _ringUpAndPay(WidgetTester tester, String query) async {
  await _openCounter(tester);
  await _search(tester, query);
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Paisay lein');
}

/// From the payment sheet: opens the customer picker, types [name], and
/// takes the offer to make them.
Future<void> _newCustomer(WidgetTester tester, String name) async {
  await tapText(tester, 'Aam gahak');
  await _typeOnTop(tester, 'Talash karein', name);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tapText(tester, "'$name' ko naya gahak banayein");
}

Future<void> _onUdhaar(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Save karein');
}

/// Types into a field on the topmost sheet. The screens underneath are still
/// mounted, with fields of the same name — the counter's own search is also
/// "Talash karein" — and a later route is later in the tree.
Future<void> _typeOnTop(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Taps the topmost button with [label]: the payment sheet's own Save is
/// still underneath the customer's.
Future<void> _tapOnTop(WidgetTester tester, String label) async {
  final button = find
      .ancestor(of: find.text(label), matching: find.byType(BlButton))
      .last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _oilWithTradePrice(Harness app) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(2500),
      wholesaleRate: Rate.rupees(2300),
      openingStock: Qty.units(50),
    ),
  );
}

/// The owner's PIN, Bilal hired as a cashier, and Bilal signed in at the
/// counter through the lock screen.
Future<void> _signInBilal(WidgetTester tester, Harness app) async {
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

/// A weighing scale's label, with its check digit.
String _label(String prefix, String plu, String value) {
  final body = '$prefix$plu$value';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = body.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return '$body${(10 - sum % 10) % 10}';
}

/// 360x800 dp — an Infinix Smart at its 720x1600 native resolution — with
/// the font at 200%, as `large_text_test.dart` lays the app out.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Every rendered piece of text still inside the screen it was drawn on,
/// checked through the transform as `large_text_test.dart` does.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}

