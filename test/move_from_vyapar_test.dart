import 'dart:convert';
import 'dart:io';

import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/import/import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// A shop leaving Vyapar or Khatabook brings its items, customers and
/// balances in one go (M52).
///
/// Every test drives the import screen by taps against a real database, and
/// reads the rows, the stock ledger and the journal back out. The Vyapar
/// item file is a real Excel 97–2003 workbook, made by Excel itself from
/// Vyapar's import template headings.
void main() {
  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

  Future<Harness> openWith(
    WidgetTester tester,
    String name,
    Uint8List bytes, {
    Future<void> Function(Harness app)? seed,
  }) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        pickImportFileProvider.overrideWithValue(() async => (name, bytes)),
      ],
    );
    await seed?.call(app);
    await openSettings(tester);
    await tapText(tester, 'Excel se laayein');
    return app;
  }

  /// What the books say, in paisa, for one system account.
  Future<int> balanceOf(Harness app, String systemKey) async =>
      await app.scalar<int>(
        'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
        'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key = '$systemKey' AND jl.deleted_at_utc IS NULL",
      ) ??
      0;

  Future<void> expectBooksBalanced(Harness app) async {
    final out = await app.scalar<int>(
      'SELECT COALESCE(SUM(debit_paisa) - SUM(credit_paisa), 0) '
      'FROM journal_lines WHERE deleted_at_utc IS NULL',
    );
    expect(out, 0, reason: 'every debit has its credit');
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  }

  group('moving from Vyapar or Khatabook', () {
    testWidgets(
      'a Vyapar item workbook comes in with its stock, and its GST and HSN are left out and said',
      (tester) async {
        final file = File(
          'packages/pk_import/test/fixtures/vyapar_items.xls',
        ).readAsBytesSync();
        final app = await openWith(
          tester,
          'Items.xls',
          file,
          seed: (app) =>
              app.seedItem(name: 'Typed by hand', rupees: 50, openingStock: 0),
        );
        await tapButton(tester, 'File chunein');

        expect(find.text('Pehchaan liya: Vyapar ka maal'), findsOneWidget);
        expect(find.text('5 line tayyar'), findsOneWidget);
        expect(
          find.textContaining(
            '3 cheezon par India ka GST rate tha (GST@12%, GST@18%, GST@5%)',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('2 cheezon ka HSN code tha'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Nahin rakhe gaye: Discount Type, Sale Discount, Item Location, '
            'Inclusive Of Tax',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('1 cheezein "BOX" mein hain'),
          findsOneWidget,
        );
        expect(
          find.textContaining('doosra unit hai (1 BOX = 10 pcs)'),
          findsOneWidget,
        );
        expect(find.text('1 kuch chhor kar aayenge'), findsOneWidget);
        expect(
          find.text(
            'Line 6: Box Matches baghair stock ke aayega; file mein -3 likha hai',
          ),
          findsOneWidget,
        );

        await tapButton(tester, '5 laayein');
        expect(find.text('5 aa gaye, 0 chhor diye'), findsOneWidget);

        final items = {
          for (final r in await app.rowsOf(
            'SELECT i.name, i.sale_rate_milli_paisa AS sale, '
            '       i.purchase_rate_milli_paisa AS cost, i.mrp_paisa AS mrp, '
            '       i.hs_code, i.tax_rule_id, i.price_includes_tax, '
            '       u.code AS unit '
            'FROM items i JOIN units u ON u.id = i.base_unit_id',
          ))
            r['name']! as String: r,
        };
        expect(items, hasLength(6));
        final sugar = items['Sugar 1kg']!;
        expect(sugar['sale'], 160 * 100 * 1000);
        expect(sugar['cost'], 140 * 100 * 1000);
        expect(sugar['mrp'], 17000);
        expect(sugar['unit'], 'kg');
        expect(items['Tapal Danedar 95g']!['sale'], 15999 * 1000);
        expect(items['Box Matches']!['unit'], 'pcs');
        expect(items['چینی لوز']!['unit'], 'kg');

        // No Indian code became a PCT code, and every item takes the tax an
        // item typed in by hand takes.
        final byHand = items['Typed by hand']!;
        for (final item in items.values) {
          expect(item['hs_code'], isNull);
          expect(item['tax_rule_id'], byHand['tax_rule_id']);
          expect(item['price_includes_tax'], byHand['price_includes_tax']);
        }

        // 25 + 40 + 12.5 on the shelf; the oversold box comes in empty.
        expect(
          await app.scalar<int>(
            'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
          ),
          77500,
        );
        // At cost: 25 x 140 + 40 x 120.50 + 12.5 x 130.
        expect(await balanceOf(app, 'inventory'), 994500);
        await expectBooksBalanced(app);
      },
    );

    testWidgets(
      'a Vyapar party report brings what customers owe onto their khata, and says what suppliers are owed',
      (tester) async {
        final app = await openWith(
          tester,
          'AllParties.csv',
          text(
            'Chishti Kiryana Store\n'
            'All Parties Report\n'
            '\n'
            'Party Name,Email,Phone No.,Receivable Balance,Payable Balance,GSTIN\n'
            'Bilal Store,,3217654321,"₹ 1,200.75",,\n'
            'Rashid Traders,,0300-1234567,,"₹ 4,500.00",27AAACR5055K1Z5\n'
            'Kamran,,,,800,\n'
            'Naveed,,,0,0,\n'
            'Total,,,"1,200.75","5,300.00",\n',
          ),
        );
        await tapButton(tester, 'File chunein');

        expect(find.text('Pehchaan liya: Vyapar ki parties'), findsOneWidget);
        expect(find.text('4 line tayyar'), findsOneWidget);
        expect(find.text('1 ne aap ko Rs 1,200.75 dene hain'), findsOneWidget);
        expect(
          find.textContaining(
            '2 suppliers jin ko aap ne Rs 5,300.00 dene hain',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('1 parties ka GSTIN tha'), findsOneWidget);
        expect(
          find.textContaining('Raqam par ₹ ka nishaan tha'),
          findsOneWidget,
        );
        expect(
          find.text('Line 9: yeh total ki line hai, koi cheez ya party nahin'),
          findsOneWidget,
        );

        // Who the two the shop owes are is the shop's to say. Customers who
        // paid ahead would come in holding an advance...
        expect(
          find.text(
            '2 jin ko aap ne dena hai, aur file nahin batati ke woh kaun '
            'hain. Woh hain:',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Pehle se paise de chuke customers');
        expect(
          find.text('2 ne pehle se diye: aap ke paas un ke Rs 5,300.00 hain'),
          findsOneWidget,
        );
        // ...but these are suppliers, as Vyapar's To Pay usually means.
        await tapText(tester, 'Suppliers');
        expect(find.text('2 kuch chhor kar aayenge'), findsOneWidget);

        await tapButton(tester, '4 laayein');
        expect(find.text('4 aa gaye, 0 chhor diye'), findsOneWidget);
        expect(
          find.textContaining(
            'Rashid Traders supplier ban kar aayega, aap ke dene wale '
            'Rs 4,500.00 ke baghair',
          ),
          findsOneWidget,
        );

        final parties = {
          for (final r in await app.rowsOf(
            'SELECT name, party_type, phone, opening_balance_paisa AS opening '
            'FROM parties',
          ))
            r['name']! as String: r,
        };
        expect(parties['Bilal Store'], {
          'name': 'Bilal Store',
          'party_type': 'customer',
          // Excel dropped the nought off the front; the khata puts it back.
          'phone': '0321 7654321',
          'opening': 120075,
        });
        expect(parties['Rashid Traders']!['party_type'], 'supplier');
        expect(parties['Rashid Traders']!['phone'], '0300 1234567');
        expect(parties['Rashid Traders']!['opening'], 0);
        expect(parties['Kamran']!['party_type'], 'supplier');
        expect(parties['Naveed']!['opening'], 0);
        expect(parties.containsKey('Total'), isFalse);

        expect(await balanceOf(app, 'accounts_receivable'), 120075);
        await expectBooksBalanced(app);
      },
    );

    testWidgets(
      'a Khatabook list comes in with udhaar owed and advances held, and the books balance',
      (tester) async {
        final app = await openWith(
          tester,
          'khatabook.csv',
          text(
            'Customer Name,Mobile Number,You will get,You will give\n'
            'Asif Bhai,0301 2223334,"₹ 2,500",\n'
            'Kamran,,,₹ 800\n'
            'Sadia,,0,0\n',
          ),
        );
        await tapButton(tester, 'File chunein');

        expect(find.text('Pehchaan liya: Khatabook'), findsOneWidget);
        expect(find.text('3 line tayyar'), findsOneWidget);
        expect(find.text('1 ne aap ko Rs 2,500.00 dene hain'), findsOneWidget);
        expect(
          find.text('1 ne pehle se diye: aap ke paas un ke Rs 800.00 hain'),
          findsOneWidget,
        );
        await tapButton(tester, '3 laayein');
        expect(find.text('3 aa gaye, 0 chhor diye'), findsOneWidget);

        final firm = (await app.services.queries.currentFirm())!;
        final khata = {
          for (final p in await app.services.queries.searchParties(firm.id))
            p.name: p,
        };
        expect(khata['Asif Bhai']!.balance, const Money.rupees(2500));
        expect(khata['Asif Bhai']!.phone, '0301 2223334');
        // You will give: the shop holds Kamran's money. A customer still,
        // in credit, and owing no supplier's bill.
        expect(khata['Kamran']!.balance, const Money.rupees(-800));
        expect(khata['Kamran']!.payable, Money.zero);
        expect(khata['Sadia']!.balance, Money.zero);

        expect(await balanceOf(app, 'accounts_receivable'), 170000);
        expect(await balanceOf(app, 'opening_balances'), -170000);
        await expectBooksBalanced(app);
      },
    );

    testWidgets(
      'a list brought in twice is never doubled, and can bring prices up to date',
      (tester) async {
        final app = await openWith(
          tester,
          'stock.csv',
          text(
            'Name,Sale price,Purchase price,Stock\n'
            'sugar 1kg,160,140,25\n'
            'Ghee 1kg,650,600,4\n',
          ),
          seed: (app) =>
              app.seedItem(name: 'Sugar 1kg', rupees: 150, openingStock: 10),
        );
        await tapButton(tester, 'File chunein');

        expect(find.text('2 line tayyar'), findsOneWidget);
        expect(find.text('1 pehle se dukaan mein hain'), findsOneWidget);
        expect(
          find.text('Line 2: sugar 1kg pehle se maal mein hai'),
          findsOneWidget,
        );
        expect(find.text('1 laayein'), findsOneWidget);

        await tapText(tester, 'File se naya karein');
        expect(
          find.textContaining('Shelf ka stock nahin badlega'),
          findsOneWidget,
        );
        await tapButton(tester, '2 laayein');
        expect(find.text('1 aa gaye, 0 chhor diye'), findsOneWidget);
        expect(find.text('1 naye kiye gaye'), findsOneWidget);

        final sugar = await app.rowsOf(
          'SELECT id, sale_rate_milli_paisa AS sale FROM items '
          "WHERE name = 'Sugar 1kg'",
        );
        expect(sugar, hasLength(1));
        expect(sugar.single['sale'], 160 * 100 * 1000);
        // The shelf is what was counted, not what the sheet says.
        expect(
          await app.scalar<int>(
            'SELECT SUM(qty_delta_thousandths) FROM stock_ledger '
            "WHERE item_id = '${sugar.single['id']}'",
          ),
          10000,
        );
        expect(await app.countIn('items'), 2);

        // The same file again: both are here, nothing is offered.
        await tapButton(tester, 'File chunein');
        expect(find.text('2 pehle se dukaan mein hain'), findsOneWidget);
        final run = tester.widget<BlButton>(
          find.widgetWithText(BlButton, '0 laayein'),
        );
        expect(run.onPressed, isNull);
        expect(await app.countIn('items'), 2);
        await expectBooksBalanced(app);
      },
    );

    testWidgets(
      'six thousand rows are read away from the screen, which says so and stays live',
      (tester) async {
        final csv = StringBuffer(
          'Item name*,Sale price,Purchase price,Opening stock quantity,'
          'Description\n',
        );
        for (var i = 1; i <= 6000; i++) {
          csv.writeln(
            'Item ${i.toString().padLeft(5, '0')},${100 + i},${80 + i},'
            '${i % 40},A line of description long enough to make it heavy',
          );
        }
        final bytes = text(csv.toString());
        expect(bytes.length, greaterThan(256 * 1024));
        await openWith(tester, 'big.csv', bytes);

        await tester.tap(find.text('File chunein'));
        await tester.pump();
        // The file is on another isolate; the screen is drawing, and says
        // what it is doing.
        expect(find.text('File parhi ja rahi hai…'), findsOneWidget);
        await settleReal(tester, until: find.text('6000 laayein'), rounds: 600);
        expect(find.text('6000 line tayyar'), findsOneWidget);
        expect(find.text('6000 laayein'), findsOneWidget);
      },
    );

    testWidgets('a column the app does not know is chosen by hand', (
      tester,
    ) async {
      final app = await openWith(
        tester,
        'list.csv',
        text('Product Title,Selling Rs,Godown Qty\nBasmati 5kg,1450,8\n'),
      );
      await tapButton(tester, 'File chunein');
      expect(
        find.text(
          'Naam aur bechne ki qeemat ke columns nahin mile. Neeche Columns '
          'mein chunein.',
        ),
        findsOneWidget,
      );

      Future<void> point(ImportField field, String heading) async {
        final box = find.byKey(ValueKey(('importField', field)));
        await tester.ensureVisible(box);
        await tester.pumpAndSettle();
        await tester.tap(box);
        await tester.pumpAndSettle();
        await tester.tap(find.text(heading).last);
        await tester.pumpAndSettle();
      }

      await point(ImportField.name, 'Product Title');
      await point(ImportField.salePrice, 'Selling Rs');
      await point(ImportField.openingStock, 'Godown Qty');
      expect(find.text('1 line tayyar'), findsOneWidget);

      await tapButton(tester, '1 laayein');
      expect(find.text('1 aa gaye, 0 chhor diye'), findsOneWidget);
      expect(
        await app.rowsOf(
          'SELECT name, sale_rate_milli_paisa AS sale FROM items',
        ),
        [
          {'name': 'Basmati 5kg', 'sale': 1450 * 100 * 1000},
        ],
      );
      expect(
        await app.scalar<int>(
          'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
        ),
        8000,
      );
    });
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the import preview for a Vyapar party report fits', (
      tester,
    ) async {
      _useASmallPhone(tester);
      await openWith(
        tester,
        'AllParties.csv',
        text(
          'Party Name,Phone No.,Receivable Balance,Payable Balance,GSTIN\n'
          'Bilal Store Wholesale and Retail,3217654321,"1,200.75",,\n'
          'Rashid Traders,0300-1234567,,"4,500",X\n',
        ),
      );
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Yeh file kaise nikalein');
      await tapButton(tester, 'File chunein');
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Columns');
      _expectNothingPaintsOffScreen(tester);
    });
  });
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

/// Every rendered piece of text still inside the screen it was drawn on.
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

