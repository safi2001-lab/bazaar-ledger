import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pk_import/pk_import.dart';
import 'package:pk_money/pk_money.dart';
import 'package:test/test.dart';

import 'xlsx_fixture.dart';

/// A shop leaving Vyapar or Khatabook brings its lists in one go (M52).
///
/// The Vyapar item files in `fixtures/` were made by Excel itself, through
/// its own automation, from Vyapar's import template headings: one saved as
/// Excel 97–2003 and one as `.xlsx`, so the two readers are held to the
/// same answer by a writer neither of them shares code with. The small
/// khata `.xls` was written by xlwt, a different program again, and is small
/// enough to live in the compound file's mini stream.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();

  group('moving from another app', () {
    test(
      'a Vyapar item file is recognised and read with prices, stock and units',
      () {
        final sheet = readSpreadsheet(
          fixture('vyapar_items_excel.xlsx'),
          fileName: 'vyapar_items_excel.xlsx',
        );
        expect(recogniseSource(sheet), ImportSource.vyaparItems);
        final plan = planItems(sheet, source: ImportSource.vyaparItems);
        expect(plan.problems, isEmpty);
        // Row 4 is empty in Excel and left out of the file; the rows after it
        // keep Excel's own numbers.
        expect(plan.rows.map((r) => r.$1), [2, 3, 5, 6, 7]);
        final byName = {for (final (_, r) in plan.rows) r.name: r};

        final sugar = byName['Sugar 1kg']!;
        expect(sugar.salePrice, const Money.rupees(160));
        expect(sugar.purchasePrice, const Money.rupees(140));
        expect(sugar.mrp, const Money.rupees(170));
        expect(sugar.openingStock, Qty.units(25));
        expect(sugar.minStock, Qty.units(5));
        expect(sugar.code, 'SG1');
        expect(sugar.category, 'Grocery');
        expect(sugar.description, 'Cheeni');
        expect(sugar.unit, 'kg');
        expect(sugar.secondaryUnit, 'g');
        expect(sugar.conversion, Qty.units(1000));

        final tapal = byName['Tapal Danedar 95g']!;
        expect(tapal.salePrice, Money.parse('159.99'));
        expect(tapal.purchasePrice, Money.parse('120.50'));
        expect(tapal.unit, 'pcs');

        final loose = byName['چینی لوز']!;
        expect(loose.purchasePrice, const Money.rupees(130));
        expect(loose.openingStock, Qty.parse('12.5'));

        final box = byName['Box Matches']!;
        expect(box.salePrice, Money.parse('1250.50'));
        // A box is not one of the units every shop starts with; it is kept
        // as written, for the shop's own units to match.
        expect(box.unit, 'BOX');
        expect(box.secondaryUnit, 'pcs');
        expect(box.conversion, Qty.units(10));

        final surf = byName['Surf Excel 1kg']!;
        expect(surf.code, '3001234567');
        expect(surf.purchasePrice, Money.parse('0.07'));
      },
    );

    test(
      'an Indian GST rate or HSN code is never carried across, and is said',
      () {
        final plan = planItems(
          readSpreadsheet(
            fixture('vyapar_items_excel.xlsx'),
            fileName: 'items.xlsx',
          ),
          source: ImportSource.vyaparItems,
        );
        // No item takes a code from the HSN column: Pakistan's PCT code agrees
        // with it only to six digits.
        expect(plan.rows.every((r) => r.$2.hsCode == null), isTrue);
        final notes = {for (final n in plan.notes) n.kind: n};
        expect(notes[ImportNoteKind.gstNotCarried]?.count, 3);
        expect(
          notes[ImportNoteKind.gstNotCarried]?.detail,
          'GST@12%, GST@18%, GST@5%',
        );
        expect(notes[ImportNoteKind.hsnNotCarried]?.count, 2);
        expect(
          notes[ImportNoteKind.columnsNotKept]?.detail,
          allOf(
            contains('Discount Type'),
            contains('Item Location'),
            contains('Inclusive Of Tax'),
          ),
        );
        expect(plan.columns.containsKey('tax'), isFalse);
        expect(plan.columns.containsKey('hsn'), isFalse);

        // A shelf Vyapar let the counter oversell comes in empty, and says so.
        final [oversold] = plan.caveats;
        expect(oversold.issue, ImportIssue.negativeStock);
        expect(oversold.name, 'Box Matches');
        expect(oversold.value, '-3');
        expect(
          plan.rows
              .firstWhere((r) => r.$2.name == 'Box Matches')
              .$2
              .openingStock,
          Qty.zero,
        );

        // A tax column in a Pakistani sheet is not read either, and the
        // preview says so in its own words.
        final local = planItems(
          readCsv('Name,Sale price,Sales tax\nGhee,650,18%\nAtta,1250,0\n'),
        );
        expect(local.notes.single.kind, ImportNoteKind.taxNotRead);
        expect(local.notes.single.count, 1);
      },
    );

    test(
      'a Vyapar party report brings balances in on the side they are owed',
      () {
        final sheet = readSpreadsheet(
          xlsxOf([
            ['Chishti Kiryana Store'],
            ['All Parties Report'],
            ['Date: 02/10/2026'],
            [''],
            [
              'Party Name',
              'Email',
              'Phone No.',
              'Receivable Balance',
              'Payable Balance',
              'Credit Limit',
              'GSTIN',
            ],
            [
              'Bilal Store',
              'bilal@example.com',
              3217654321,
              '₹ 1,200.75',
              '',
              5000,
              '',
            ],
            [
              'Rashid Traders',
              '',
              '0300-1234567',
              '',
              4500,
              '',
              '27AAACR5055K1Z5',
            ],
            ['Naveed', '', '', 0, 0, '', ''],
            ['Ali Halwai', '', '', '', 300, '', ''],
            ['Total', '', '', 1200.75, 4800, '', ''],
          ]),
          fileName: 'AllParties.xlsx',
        );
        expect(recogniseSource(sheet), ImportSource.vyaparParties);
        final plan = planParties(sheet, source: ImportSource.vyaparParties);
        final byName = {for (final (_, r) in plan.rows) r.name: r};
        expect(byName.keys, [
          'Bilal Store',
          'Rashid Traders',
          'Naveed',
          'Ali Halwai',
        ]);

        // To receive: the customer owes the shop.
        final bilal = byName['Bilal Store']!;
        expect(bilal.isSupplier, isFalse);
        expect(bilal.balance, Money.parse('1200.75'));
        expect(bilal.phone, '3217654321');
        expect(bilal.creditLimit, const Money.rupees(5000));

        // To pay, and nothing in the row says who they are: in Vyapar, that
        // is somebody the shop buys from. Their balance waits for a bill.
        final rashid = byName['Rashid Traders']!;
        expect(rashid.isSupplier, isTrue);
        expect(rashid.owesShop, const Money.rupees(-4500));
        expect(byName['Naveed']!.balance, Money.zero);
        expect(plan.owedUnsaid, 2);
        expect(plan.caveats.map((c) => (c.issue, c.name, c.value)), [
          (ImportIssue.supplierOwed, 'Rashid Traders', '4,500.00'),
          (ImportIssue.supplierOwed, 'Ali Halwai', '300.00'),
        ]);

        // The report's own total is not a party.
        expect(plan.problems.single.issue, ImportIssue.totalLine);
        expect(plan.problems.single.line, 10);

        final notes = {for (final n in plan.notes) n.kind: n};
        expect(notes[ImportNoteKind.gstinNotKept]?.count, 1);
        expect(notes.containsKey(ImportNoteKind.rupeeSign), isTrue);
        expect(notes[ImportNoteKind.columnsNotKept]?.detail, 'Email');

        // The shop says the ones it owes are customers who paid ahead: then
        // each is a customer holding an advance, and it all comes in.
        final asCustomers = planParties(
          sheet,
          source: ImportSource.vyaparParties,
          owedAreSuppliers: false,
        );
        final rashidAhead = asCustomers.rows
            .firstWhere((r) => r.$2.name == 'Rashid Traders')
            .$2;
        expect(rashidAhead.isSupplier, isFalse);
        expect(rashidAhead.balance, const Money.rupees(-4500));
        expect(asCustomers.caveats, isEmpty);
      },
    );

    test(
      'a Khatabook list reads You will get as owed to the shop and You will give as owed by it',
      () {
        final sheet = readSpreadsheet(
          xlsxOf([
            ['Customer Name', 'Mobile Number', 'You will get', 'You will give'],
            ['Asif Bhai', '0301 2223334', '₹ 2,500', ''],
            ['Kamran', '', '', '₹ 800'],
            ['Sadia', '', 0, 0],
          ]),
          fileName: 'khatabook.xlsx',
        );
        expect(recogniseSource(sheet), ImportSource.khatabook);
        final plan = planParties(sheet, source: ImportSource.khatabook);
        final byName = {for (final (_, r) in plan.rows) r.name: r};
        expect(byName['Asif Bhai']!.balance, const Money.rupees(2500));
        expect(byName['Asif Bhai']!.phone, '0301 2223334');
        // A Khatabook customer the shop owes paid ahead; they stay a customer.
        expect(byName['Kamran']!.isSupplier, isFalse);
        expect(byName['Kamran']!.balance, const Money.rupees(-800));
        expect(byName['Sadia']!.balance, Money.zero);
        expect(plan.caveats, isEmpty);
        expect(
          plan.notes.map((n) => n.kind),
          contains(ImportNoteKind.rupeeSign),
        );

        // The same list with the direction in a column of its own.
        final single = planParties(
          readCsv(
            'Name,Balance,Status\n'
            'Asif Bhai,"2,500",You will get\n'
            'Kamran,800,You will give\n',
          ),
          source: ImportSource.khatabook,
        );
        expect(single.rows.map((r) => r.$2.balance), [
          const Money.rupees(2500),
          const Money.rupees(-800),
        ]);
      },
    );

    test(
      'balances written with To Receive, To Pay, Dr and Cr read the right way',
      () {
        final plan = planParties(
          readCsv(
            'Name,Closing Balance,Dr/Cr,Type\n'
            'Akram,"1,000",Dr,\n'
            'Basit,250,Cr,\n'
            'Chaudhry,500 Cr,,\n'
            'Dawood,(300),,\n'
            'Ehsan,lots,,\n'
            'Faisal Mills,"1,500",,Supplier\n'
            'Ghulam,700 To Receive,,\n',
          ),
        );
        final balances = {
          for (final (_, r) in plan.rows) r.name: (r.balance, r.isSupplier),
        };
        expect(balances, {
          'Akram': (const Money.rupees(1000), false),
          'Basit': (const Money.rupees(-250), false),
          'Chaudhry': (const Money.rupees(-500), false),
          'Dawood': (const Money.rupees(-300), false),
          // A plain balance on a supplier's row is what the shop owes them.
          'Faisal Mills': (const Money.rupees(1500), true),
          'Ghulam': (const Money.rupees(700), false),
        });
        expect(plan.problems.single.issue, ImportIssue.notAnAmount);
        expect(plan.problems.single.value, 'lots');

        SheetAmount amount(String s) => readAmount(s)!;
        expect(amount('₹ 1,25,000.50').money, Money.parse('125000.50'));
        expect(amount('₹ 1,25,000.50').rupeeSign, isTrue);
        expect(amount('Rs. 1,250').money, const Money.rupees(1250));
        expect(amount('PKR 99').rupeeSign, isFalse);
        expect(amount('1,200 To Receive').direction, Direction.theyOwe);
        expect(amount('500 (To Pay)').direction, Direction.shopOwes);
        expect(amount('500 (To Pay)').money, const Money.rupees(500));
        expect(amount('-75').money, const Money.rupees(-75));
        expect(amount('159.99999999999997').money, const Money.rupees(160));
        expect(readAmount('-'), isNull);
        expect(readAmount('500/600'), isNull);
        expect(readAmount('lots'), isNull);
      },
    );

    test(
      'old binary .xls workbooks are read, from Excel and from other programs',
      () {
        final fromXls = planItems(
          readSpreadsheet(fixture('vyapar_items.xls'), fileName: 'items.xls'),
          source: ImportSource.vyaparItems,
        );
        final fromXlsx = planItems(
          readSpreadsheet(
            fixture('vyapar_items_excel.xlsx'),
            fileName: 'items.xlsx',
          ),
          source: ImportSource.vyaparItems,
        );
        String describe(ImportPlan<ItemRow> p) => [
          for (final (line, r) in p.rows)
            [
              line,
              r.name,
              r.code,
              r.salePrice,
              r.purchasePrice,
              r.mrp,
              r.openingStock,
              r.unit,
              r.secondaryUnit,
              r.conversion,
            ].join('|'),
        ].join('\n');
        expect(describe(fromXls), describe(fromXlsx));
        expect(fromXls.rows, hasLength(5));

        // Written by another program, and small enough to sit in the mini
        // stream; a phone number Excel kept as a number keeps its digits.
        final khata = readSpreadsheet(
          fixture('khata_small.xls'),
          fileName: 'khata.xls',
        );
        expect(recogniseSource(khata), ImportSource.vyaparParties);
        final parties = planParties(khata, owedAreSuppliers: false);
        expect(
          [for (final (_, r) in parties.rows) (r.name, r.phone, r.balance)],
          [
            ('Rashid Traders', '0300-1234567', const Money.rupees(-4500)),
            ('Bilal Store', '3217654321', Money.parse('1200.75')),
          ],
        );

        // Six hundred names, every third in Urdu, run on across the shared
        // strings' CONTINUE records; every one comes back as it was written.
        final long = planItems(
          readSpreadsheet(fixture('long_list.xls'), fileName: 'list.xls'),
        );
        expect(long.problems, isEmpty);
        expect(long.rows, hasLength(600));
        for (final (i, (_, row)) in long.rows.indexed) {
          final n = i + 1;
          expect(
            row.name,
            n % 3 == 0
                ? 'Item $n مال number $n of the long list'
                : 'Item $n plain name number $n of the long list',
          );
          expect(row.salePrice, Money.paisa(n * 100 + 25 * (n % 4)));
          expect(row.openingStock, Qty.units(n % 50));
        }

        // A password, or Excel 95, is said in words.
        expect(
          () => readSpreadsheet(Uint8List(8), fileName: 'old.xls'),
          throwsA(isA<ImportRefused>()),
        );
      },
    );

    test(
      'web exports saved as .xls — an HTML table or Excel 2003 XML — are read',
      () {
        final html = readSpreadsheet(
          Uint8List.fromList(
            utf8.encode(
              '<html><body><h1>Items</h1><table border="1">'
              '<tr><th>Item Name</th><th>Sale Price</th></tr>'
              '<tr><td>Sugar &amp; Salt</td><td><b>Rs 160</b></td></tr>'
              '<tr><td>Daal&nbsp;Chana</td><td>310</td></tr>'
              '</table></body></html>',
            ),
          ),
          fileName: 'items.xls',
        );
        expect(planItems(html).rows.map((r) => (r.$2.name, r.$2.salePrice)), [
          ('Sugar & Salt', const Money.rupees(160)),
          ('Daal Chana', const Money.rupees(310)),
        ]);

        final xml = readSpreadsheet(
          Uint8List.fromList(
            utf8.encode(
              '<?xml version="1.0"?>'
              '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
              'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
              '<Worksheet ss:Name="Stock"><Table>'
              '<Row><Cell><Data ss:Type="String">Name</Data></Cell>'
              '<Cell><Data ss:Type="String">Price</Data></Cell></Row>'
              '<Row><Cell><Data ss:Type="String">Ghee</Data></Cell>'
              '<Cell ss:Index="2"><Data ss:Type="Number">650</Data></Cell></Row>'
              '<Row ss:Index="4"><Cell><Data ss:Type="String">Atta</Data></Cell>'
              '<Cell><Data ss:Type="Number">1250</Data></Cell></Row>'
              '</Table></Worksheet></Workbook>',
            ),
          ),
          fileName: 'stock.xls',
        );
        final plan = planItems(xml);
        expect(plan.rows.map((r) => (r.$1, r.$2.name)), [
          (2, 'Ghee'),
          (4, 'Atta'),
        ]);
      },
    );

    test('a column the app does not know is pointed at its field by hand', () {
      final sheet = readCsv(
        'Product Title,Selling Rs,Godown Qty\n'
        'Basmati 5kg,1450,8\n',
      );
      final found = findColumns(sheet, ImportKind.items);
      expect(found.fields, isEmpty);
      expect(found.headings, ['Product Title', 'Selling Rs', 'Godown Qty']);
      expect(() => planItems(sheet), throwsA(isA<ImportRefused>()));

      final byHand = found
          .withField(ImportField.name, 0)
          .withField(ImportField.salePrice, 1)
          .withField(ImportField.openingStock, 2);
      final plan = planItems(sheet, columns: byHand);
      final (line, rice) = plan.rows.single;
      expect(line, 2);
      expect(rice.name, 'Basmati 5kg');
      expect(rice.salePrice, const Money.rupees(1450));
      expect(rice.openingStock, Qty.units(8));

      // A column holds one field: pointing another at it lets the first go.
      final moved = byHand.withField(ImportField.purchasePrice, 1);
      expect(moved.fields[ImportField.purchasePrice], 1);
      expect(moved.fields.containsKey(ImportField.salePrice), isFalse);
    });

    test(
      "a list made with the headings on screen is recognised as the shop's own",
      () {
        expect(
          recogniseSource(
            readCsv(
              'Name,Sale price,Purchase price,Stock,Unit\nGhee,650,600,4,kg\n',
            ),
          ),
          ImportSource.bazaarLedger,
        );
        final khata = readCsv(
          'Name,Phone,Balance,Type\nBilal,0321 7654321,1200,Customer\n',
        );
        expect(recogniseSource(khata), ImportSource.bazaarLedger);
        expect(guessKind(khata), ImportKind.parties);
        // Somebody else's headings, read the same but not claimed as ours;
        // and a lone Name says nothing about which list it is.
        expect(
          recogniseSource(
            readCsv('Item name,Sale price,Purchase price,Opening quantity\n'),
          ),
          isNull,
        );
        expect(recogniseSource(readCsv('Name\nGhee\n')), isNull);
      },
    );

    test('units are read as the shop keeps them', () {
      expect(unitCode('PIECES'), 'pcs');
      expect(unitCode('Nos'), 'pcs');
      expect(unitCode('Kilograms (Kg)'), 'kg');
      expect(unitCode('GRAMMES'), 'g');
      expect(unitCode('Ltr'), 'l');
      expect(unitCode('Dozens'), 'dozen');
      expect(unitCode('Bori'), 'Bori');
    });

    test(
      'five thousand rows are read and checked without stalling',
      () {
        final rows = <List<Object>>[
          [
            'Item name*',
            'Sale price',
            'Purchase price',
            'Opening stock quantity',
            'HSN',
            'Tax Rate',
          ],
          for (var i = 1; i <= 5000; i++)
            ['Item $i', 100 + i, 80 + i, i % 40, 1006, 'GST@5%'],
        ];
        final file = xlsxOf(rows);
        final clock = Stopwatch()..start();
        final sheet = readSpreadsheet(file, fileName: 'big.xlsx');
        final source = recogniseSource(sheet) ?? ImportSource.other;
        final plan = planItems(sheet, source: source);
        clock.stop();
        expect(source, ImportSource.vyaparItems);
        expect(plan.rows, hasLength(5000));
        expect(plan.problems, isEmpty);
        // A bound on stalling, not a benchmark: about two seconds on a desktop,
        // and a loaded CI runner gets room. The screen reads a file this size
        // on an isolate anyway, so the shop sees it reading, not frozen.
        expect(clock.elapsed, lessThan(const Duration(seconds: 30)));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
