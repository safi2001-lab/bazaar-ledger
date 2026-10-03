import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// An old bill says what it said on the day it was made (M62).
///
/// myBillBook's most-agreed complaint (+550): a shopkeeper corrected a
/// customer's address in the party list and every bill that customer had
/// ever been given changed its address with it — including bills already
/// filed with the customer's accounts, and the sales tax invoices on which
/// the buyer's address and registration numbers are particulars the law
/// asks for. A bill is a record of a sale on a day; the khata is a record
/// of a person today. The two are allowed to disagree, and the bill is the
/// one that may not move.
///
/// Each test makes a bill at the counter the way the counter makes it —
/// the customer picked from the khata, so the draft carries the party and
/// the name and nothing else — then edits the customer (name, address,
/// phone, NTN and STRN, as M31's editor saves them) and the item (its name
/// and its price), and reads the old bill back every way it can leave the
/// shop.
///
/// What this found: the counter never wrote the customer's address, NTN or
/// STRN on the bill, so every paper fell back to the khata's record read
/// today. A bill made for "Shop 5, Shah Alam Market" reprinted as "Plot 9,
/// Badami Bagh" the moment the address was corrected, on the till roll,
/// every PDF design and the sales tax invoice alike. The document writer
/// now takes them from the khata as the bill is written, beneath every
/// screen.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String pcs;
  late String rashid;
  late String oil;

  const onTheDay = PartyDraft(
    name: 'Rashid Traders',
    phone: '0300-4471203',
    addressLine1: 'Shop 5, Shah Alam Market',
    city: 'Lahore',
    ntn: '7654321-0',
    strn: '3277876123455',
  );

  // Everything that names the customer or the goods as they are now, after
  // the edit. Not one of these may reach the old bill.
  const today = PartyDraft(
    name: 'Rashid Brothers',
    phone: '0333-9998887',
    addressLine1: 'Plot 9, Badami Bagh',
    city: 'Faisalabad',
    ntn: '1111111-1',
    strn: '9999999999999',
  );
  const nowWords = [
    'Brothers',
    'Badami',
    'Faisalabad',
    '1111111-1',
    '9999999999999',
    'Dalda',
    '2,900.00',
  ];
  // What every paper says of the bill: whose it is and what was sold.
  const thenWords = ['Rashid', 'Traders', 'Cooking', '5,000.00'];
  // What the PDF designs print besides: the address and registration
  // numbers the bill was made with. The till roll leaves them off the
  // customer's own copy (M51) and prints the address only on the sheet that
  // travels with the goods.
  const thenAddress = ['Shah', 'Alam', '7654321-0', '3277876123455'];

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 9, 15, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    rashid = await shop.catalogue.addParty(shop.actorNow(), onTheDay);
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(2500),
        hsCode: '1507.9000',
        openingStock: Qty.units(50),
        openingRate: Rate.rupees(2000),
      ),
    );
    clock.advance(const Duration(minutes: 1));
  });

  tearDown(() => shop.close());

  /// Two tins at Rs 2,500, Rs 1,000 paid in cash, to Rashid — with the
  /// draft the counter's tender sheet builds: the party picked from the
  /// khata and its name, nothing more.
  Future<PostedSale> sellAtTheCounter() async {
    final sale = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: const Money.rupees(1000),
          ),
        ],
      ),
    );
    clock.advance(const Duration(minutes: 1));
    return sale;
  }

  /// The customer and the item edited as the shopkeeper edits them: the
  /// customer moved shop, changed number, registered again and renamed the
  /// firm; the item renamed and repriced.
  Future<void> editEverything() async {
    await shop.catalogue.updateParty(shop.actorNow(), rashid, today);
    await shop.catalogue.updateItem(
      shop.actorNow(),
      oil,
      ItemDraft(
        name: 'Dalda Oil Tin',
        baseUnitId: pcs,
        saleRate: Rate.rupees(2900),
        hsCode: '1507.9000',
      ),
    );
    clock.advance(const Duration(minutes: 1));
  }

  void saysWhatItSaid(
    String paper,
    String where, {
    List<String> also = const [],
  }) {
    for (final word in [...thenWords, ...also]) {
      expect(paper, contains(word), reason: '$where lost "$word"');
    }
    for (final word in nowWords) {
      expect(
        paper,
        isNot(contains(word)),
        reason: '$where says "$word", which the khata only says today',
      );
    }
  }

  group('an old bill keeps its word', () {
    test('the paper names the customer, their address and tax numbers, and '
        'each line, as they were on the day', () async {
      final sale = await sellAtTheCounter();
      await editEverything();

      final bill = (await shop.billPaper(sale.documentId))!.receipt;
      expect(bill.customerName, 'Rashid Traders');
      expect(bill.customerAddress, 'Shop 5, Shah Alam Market, Lahore');
      expect(bill.customerNtn, '7654321-0');
      expect(bill.customerStrn, '3277876123455');
      expect(bill.lines.single.name, 'Cooking Oil 5L');
      expect(bill.lines.single.rate, Rate.rupees(2500));
      expect(bill.lines.single.amount, const Money.rupees(5000));
      expect(bill.total, const Money.rupees(5000));
    });

    test('the reprint on the till roll, and the picture drawn from it, say '
        'what the bill said', () async {
      final sale = await sellAtTheCounter();
      await editEverything();

      const renderer = ThermalReceiptRenderer();
      for (final paper in ReceiptPaper.values) {
        // The picture (M30) is these same lines drawn as a PNG: it reads
        // `toPreview` of the same dressed receipt, so what is proved of
        // the lines is proved of the picture.
        final bill = (await shop.billPaper(
          sale.documentId,
          thermal: paper,
        ))!.receipt;
        saysWhatItSaid(
          renderer.toPreview(bill, paper: paper).join('\n'),
          '$paper',
          // The rate each line was sold at, as the roll prints it.
          also: ['2 pcs x 2,500.00'],
        );
      }
      // The duplicate from the sheet picker, the way a reprint goes out.
      final duplicate = (await shop.billPaper(
        sale.documentId,
        copy: ReceiptCopy.duplicate,
      ))!.receipt;
      saysWhatItSaid(
        renderer.toPreview(duplicate).join('\n'),
        'duplicate',
        also: ['2 pcs x 2,500.00'],
      );
    });

    test('every PDF design, the sales tax invoice too, says what the bill '
        'said', () async {
      final sale = await sellAtTheCounter();
      await editEverything();

      const renderer = ThermalReceiptRenderer();
      for (final theme in BillTheme.values) {
        final design = BillDesign(theme: theme);
        final bill = (await shop.billPaper(
          sale.documentId,
          design: design,
        ))!.receipt;
        final pdf = String.fromCharCodes(
          await renderer.toPdf(bill, design: design, compress: false),
        );
        saysWhatItSaid(
          pdf,
          '$theme',
          also: [
            ...thenAddress,
            // The rate each line was sold at. The tax invoice's Rate
            // column is the tax's, and its line reads value before tax.
            if (theme != BillTheme.taxInvoice) '2,500.00',
          ],
        );
      }
    });

    test('the WhatsApp message greets the customer by the name on the bill, '
        'and is sent to the number the khata has today', () async {
      final sale = await sellAtTheCounter();
      await editEverything();

      final bill = (await shop.billPaper(sale.documentId))!.receipt;
      final message = billMessage(bill);
      expect(message, contains('Assalam-o-Alaikum Rashid Traders'));
      expect(message, contains('Kul: Rs 5,000.00'));
      expect(message, isNot(contains('Brothers')));

      // The name on the paper; the number on the khata now. A customer who
      // changed their number is reached on the new one — a number is how
      // to reach somebody, not something the bill said.
      final to = (await shop.queries.recipientOf(firmId, sale.documentId))!;
      expect(to.name, 'Rashid Traders');
      expect(to.phone, '0333-9998887');
    });

    test('the transporter\'s copy rings the buyer on today\'s number, and '
        'names them and their address as the bill did', () async {
      // The one place a bill prints a phone (M51): the driver rings the
      // buyer from the adda, so it is the number that answers today. The
      // documents table has no column for a phone; adding one would be a
      // schema change for a number that is wrong the day it changes.
      final sale = await sellAtTheCounter();
      await editEverything();

      final copy = (await shop.billPaper(
        sale.documentId,
        copy: ReceiptCopy.transporter,
      ))!.receipt;
      final paper = const ThermalReceiptRenderer().toPreview(copy).join('\n');
      expect(paper, contains('0333-9998887'));
      expect(paper, contains('Traders'));
      expect(paper, contains('Shah Alam'));
      expect(paper, isNot(contains('Badami')));
    });

    test(
      'the khata\'s statement line for the bill is the bill as it was',
      () async {
        final sale = await sellAtTheCounter();
        await editEverything();

        final entries = await shop.queries.partyLedger(firmId, rashid);
        final line = entries.singleWhere((e) => e.reference == sale.docNo);
        expect(line.amount, const Money.rupees(5000));

        final statement = await shop.reports.run(
          ReportKind.partyStatement,
          firmId: firmId,
          period: ReportPeriod.day(const BusinessDate('2026-09-15')),
          today: const BusinessDate('2026-09-15'),
          filters: ReportFilters(partyId: rashid, partyName: 'Rashid Brothers'),
        );
        final row = statement.rows.singleWhere(
          (r) => r.cells.contains(sale.docNo),
        );
        expect(row.cells, contains(const Money.rupees(5000)));
        for (final cell in row.cells) {
          for (final word in nowWords) {
            expect('$cell', isNot(contains(word)));
          }
        }
      },
    );

    test(
      'every report row that shows the bill names it as it was; the '
      'reports about the customer or the item name them as they are',
      () async {
        final sale = await sellAtTheCounter();
        await editEverything();
        final day = ReportPeriod.day(const BusinessDate('2026-09-15'));

        Future<ReportTable> run(ReportKind kind) => shop.reports.run(
          kind,
          firmId: firmId,
          period: day,
          today: const BusinessDate('2026-09-15'),
        );

        // A row per bill, or per line of a bill: the bill's own words.
        for (final kind in [
          ReportKind.saleReport,
          ReportKind.allTransactions,
          ReportKind.billWiseProfit,
          ReportKind.dayBook,
          ReportKind.annexC,
        ]) {
          final table = await run(kind);
          final row = table.rows.firstWhere(
            (r) => r.cells.any((c) => '$c'.contains(sale.docNo)),
            orElse: () => table.rows.firstWhere(
              (r) => r.cells.contains('Rashid Traders'),
            ),
          );
          expect(row.cells, contains('Rashid Traders'), reason: '$kind');
          for (final r in table.rows) {
            for (final cell in r.cells) {
              for (final word in nowWords) {
                expect('$cell', isNot(contains(word)), reason: '$kind: $cell');
              }
            }
          }
        }
        final annex = await run(ReportKind.annexC);
        expect(
          annex.rows.expand((r) => r.cells),
          contains('Cooking Oil 5L'),
          reason: 'Annex-C files the line as it was sold',
        );

        // A report about the customer, or about the item, is about them as
        // they are: the khata is one person whatever they are called now,
        // and a renamed item is still the same shelf. These are not rows of
        // the bill.
        final byParty = await run(ReportKind.partyProfitAndLoss);
        expect(
          byParty.rows.expand((r) => r.cells),
          contains('Rashid Brothers'),
        );
        final byItem = await run(ReportKind.salesByItem);
        expect(byItem.rows.expand((r) => r.cells), contains('Dalda Oil Tin'));
      },
    );

    test('a bill written before the counter kept the address falls back to '
        'the khata\'s record, and only for what it never kept', () async {
      // The fallback M51 left in the bill's extras, proved to be exactly
      // that: a bill whose row holds no address, NTN or STRN (every bill
      // before M62 — the counter never wrote them) reads the khata's; the
      // name, the lines and the rates are the bill's own on every bill.
      final sale = await sellAtTheCounter();
      await shop.database.customStatement(
        'UPDATE documents SET party_address_snapshot = NULL, '
        'party_ntn_snapshot = NULL, party_strn_snapshot = NULL WHERE id = ?',
        [sale.documentId],
      );
      await editEverything();

      final bill = (await shop.billPaper(sale.documentId))!.receipt;
      expect(bill.customerName, 'Rashid Traders');
      expect(bill.lines.single.name, 'Cooking Oil 5L');
      expect(bill.lines.single.rate, Rate.rupees(2500));
      expect(bill.customerAddress, 'Plot 9, Badami Bagh, Faisalabad');
      expect(bill.customerNtn, '1111111-1');
      expect(bill.customerStrn, '9999999999999');
    });

    test('what the counter typed for the bill wins over the khata, and a '
        'walk-in is never given a khata\'s address', () async {
      // The M59 walk-in: a name and a CNIC typed at the counter, no khata.
      final walkIn = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          partyName: 'Imran Butt',
          partyNtn: '35202-1234567-1',
          lines: [
            SaleLineDraft(
              itemId: oil,
              itemName: 'Cooking Oil 5L',
              qty: Qty.units(1),
              baseQty: Qty.units(1),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(2500),
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: const Money.rupees(2500),
            ),
          ],
        ),
      );
      final row =
          (await shop.database
                  .customSelect(
                    'SELECT party_name_snapshot, party_address_snapshot, '
                    "party_ntn_snapshot FROM documents WHERE id = '${walkIn.documentId}'",
                  )
                  .getSingle())
              .data;
      expect(row['party_name_snapshot'], 'Imran Butt');
      expect(row['party_ntn_snapshot'], '35202-1234567-1');
      expect(row['party_address_snapshot'], isNull);
    });
  });
}
