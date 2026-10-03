import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A bill paid two ways is two payments, in every report and every export
/// (M62).
///
/// The top review of Vyapar in 2026 (+403): a bill paid part in cash and
/// part online comes out of its exported reports wrong — one mode for the
/// whole bill, so the cash in the export is not the cash in the drawer and
/// the JazzCash total is not what JazzCash says. In Pakistan the split is
/// the everyday case: Rs 3,000 from the wallet in the pocket and the rest
/// sent from the phone.
///
/// One day of a shop: a bill to Rashid on udhaar (Rs 2,500); a second bill
/// to him of Rs 5,000 paid at the counter Rs 3,000 in cash and Rs 2,000 by
/// JazzCash; and the udhaar paid off later the same day, Rs 1,500 in cash
/// and Rs 1,000 by JazzCash. The receipt sheet takes one mode a receipt, so
/// the khata's split is two receipts, and the reports must treat the
/// counter's split the same way: two payments, each its own mode and
/// amount. Every report that shows money is read, and every figure is tied
/// to the others: Rs 4,500 came in as cash and Rs 3,000 by JazzCash,
/// Rs 7,500 in all, on Rs 7,500 of sales.
///
/// What this found: the Payment-mode summary, the Z report, the Cash flow,
/// the Cash book and the bank statement already kept the tenders apart.
/// The Sale report's "Paid by" named both modes but not how much each
/// (so the export could not be summed by mode); All Transactions said
/// nothing of how anything was paid; and the Day Book showed the bill's
/// Rs 5,000 in as one figure with no word of the split. Each now says each
/// tender with its amount: "Cash 3,000.00 + JazzCash 2,000.00".
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String jazz;
  late String pcs;
  late String rashid;
  late String oil;
  late PostedSale udhaar;
  late PostedSale split;

  final day = ReportPeriod.day(const BusinessDate('2026-09-15'));
  const both = 'Cash 3,000.00 + JazzCash 2,000.00';

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 9, 15, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    final accounts = await shop.queries.paymentAccounts(firmId);
    cash = accounts.firstWhere((a) => a.modeLabel == 'cash').id;
    jazz = accounts.firstWhere((a) => a.modeLabel == 'jazzcash').id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    rashid = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'Rashid Traders', phone: '0300-4471203'),
    );
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(2500),
        tracksStock: false,
      ),
    );
    clock.advance(const Duration(minutes: 1));

    SaleLineDraft tins(int n) => SaleLineDraft(
      itemId: oil,
      itemName: 'Cooking Oil 5L',
      qty: Qty.units(n),
      baseQty: Qty.units(n),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(2500),
    );
    udhaar = await shop.postSale(
      shop.actorNow(),
      SaleDraft(partyId: rashid, partyName: 'Rashid Traders', lines: [tins(1)]),
    );
    clock.advance(const Duration(minutes: 1));
    split = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        lines: [tins(2)],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: const Money.rupees(3000),
          ),
          TenderDraft(
            paymentAccountId: jazz,
            mode: 'jazzcash',
            amount: const Money.rupees(2000),
            reference: 'TID 88123',
          ),
        ],
      ),
    );
    clock.advance(const Duration(minutes: 1));
    // The udhaar paid off two ways: two receipts, as the sheet takes them.
    for (final (mode, account, rupees) in [
      ('cash', cash, 1500),
      ('jazzcash', jazz, 1000),
    ]) {
      await shop.recordReceipt(
        shop.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: Money.rupees(rupees),
          mode: mode,
          paymentAccountId: account,
        ),
      );
      clock.advance(const Duration(minutes: 1));
    }
  });

  tearDown(() => shop.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportFilters filters = ReportFilters.none,
  }) => shop.reports.run(
    kind,
    firmId: firmId,
    period: day,
    today: day.to,
    filters: filters,
  );

  /// The cell under [column] in the first row whose cells include [key].
  Object? cell(ReportTable t, Object key, String column) => t.rows
      .firstWhere((r) => r.cells.contains(key))
      .cells[t.columns.indexWhere((c) => c.title == column)];

  List<ReportRow> lines(ReportTable t) =>
      t.rows.where((r) => r.style == RowStyle.line).toList();

  group('a split payment is two payments', () {
    test('the bill\'s own paper lists each tender with its amount', () async {
      final bill = (await shop.billPaper(split.documentId))!.receipt;
      expect(
        [for (final t in bill.tenders) (t.label, t.amount)],
        [
          ('Cash', const Money.rupees(3000)),
          ('JazzCash', const Money.rupees(2000)),
        ],
      );
      expect(bill.paid, const Money.rupees(5000));
    });

    test('the Sale report says how much each way, and its totals are the '
        'bills\'', () async {
      final t = await run(ReportKind.saleReport);
      expect(cell(t, split.docNo, 'Paid by'), both);
      expect(cell(t, split.docNo, 'Received'), const Money.rupees(5000));
      // Paid off later by two receipts, which the khata allotted to it.
      expect(
        cell(t, udhaar.docNo, 'Paid by'),
        'Cash 1,500.00 + JazzCash 1,000.00',
      );
      expect(t.summary[1].amount, const Money.rupees(7500));

      // Narrowed to JazzCash it still lists the bill whole, and says how
      // much of it was JazzCash rather than letting the whole stand as
      // JazzCash's.
      final jazzOnly = await run(
        ReportKind.saleReport,
        filters: const ReportFilters(paymentMode: 'jazzcash'),
      );
      expect(cell(jazzOnly, split.docNo, 'Paid by'), both);
    });

    test('All Transactions says how each bill and each receipt was paid, '
        'and lists a tender taken with a bill once, inside the bill', () async {
      final t = await run(ReportKind.allTransactions);
      expect(cell(t, split.docNo, 'Paid by'), both);
      expect(cell(t, split.docNo, 'Paid'), const Money.rupees(5000));
      final receipts = [
        for (final r in lines(t))
          if (r.cells[2] == 'Payment in')
            (
              r.cells[4],
              r.cells[t.columns.indexWhere((c) => c.title == 'Paid by')],
            ),
      ];
      expect(receipts, [
        (const Money.rupees(1500), 'Cash'),
        (const Money.rupees(1000), 'JazzCash'),
      ]);
      // Two bills and two receipts: the counter's two tenders are not
      // listed again as payments of their own.
      expect(lines(t), hasLength(4));
      expect(t.summary.first.count, 4);
    });

    test('the Day Book takes the bill\'s money in once and says how it '
        'came', () async {
      final t = await run(ReportKind.dayBook);
      final row = lines(t).singleWhere((r) => r.cells[1] == split.docNo);
      expect(row.cells[4], contains(both));
      expect(row.cells[6], const Money.rupees(5000));
      expect(t.summary.first.amount, const Money.rupees(7500));
      // A bill paid one way, and a receipt, read as they always have.
      for (final r in lines(t)) {
        if (r.cells[1] != split.docNo) {
          expect('${r.cells[4]}', isNot(contains('+')), reason: '${r.cells}');
        }
      }
    });

    test('the drawer, the wallet and the modes each count only their own '
        'part, and every total ties', () async {
      final flow = await run(ReportKind.cashflow);
      expect(
        cell(flow, 'Sales at the counter', 'Cash'),
        const Money.rupees(3000),
      );
      expect(
        cell(flow, 'Sales at the counter', 'Bank and wallets'),
        const Money.rupees(2000),
      );
      expect(
        cell(flow, 'Received on khatas', 'Cash'),
        const Money.rupees(1500),
      );
      expect(
        cell(flow, 'Received on khatas', 'Bank and wallets'),
        const Money.rupees(1000),
      );
      expect(cell(flow, 'Total money in', 'Total'), const Money.rupees(7500));

      final book = await run(ReportKind.cashBook);
      expect(
        lines(book)
            .where((r) => '${r.cells[2]}'.contains(split.docNo))
            .map((r) => r.cells[3]),
        [const Money.rupees(3000)],
        reason: 'the drawer took Rs 3,000 of the bill, not Rs 5,000',
      );
      expect(
        cell(book, 'Closing balance', 'Balance'),
        const Money.rupees(4500),
      );

      final wallets =
          (await shop.database
                  .customSelect(
                    'SELECT ledger_account_id AS id FROM payment_accounts '
                    "WHERE mode_label = 'jazzcash'",
                  )
                  .getSingle())
              .read<String>('id');
      final statement = await run(
        ReportKind.bankStatement,
        filters: ReportFilters(accountId: wallets, accountName: 'Wallets'),
      );
      expect(
        cell(statement, 'Sale ${split.docNo}', 'Deposit'),
        const Money.rupees(2000),
      );
      expect(
        cell(statement, 'Closing balance', 'Balance'),
        const Money.rupees(3000),
      );

      final modes = await run(ReportKind.paymentModes);
      expect(cell(modes, 'Cash', 'Sales paid by it'), const Money.rupees(3000));
      expect(
        cell(modes, 'Cash', 'Received on khatas'),
        const Money.rupees(1500),
      );
      expect(
        cell(modes, 'JazzCash', 'Sales paid by it'),
        const Money.rupees(2000),
      );
      expect(
        cell(modes, 'JazzCash', 'Received on khatas'),
        const Money.rupees(1000),
      );
      expect(
        cell(modes, 'Udhaar', 'Sales paid by it'),
        const Money.rupees(2500),
      );
      expect(
        cell(modes, 'Total', 'Sales paid by it'),
        const Money.rupees(7500),
      );
      expect(cell(modes, 'Total', 'Total collected'), const Money.rupees(7500));

      final z = await run(ReportKind.dailySummary);
      expect(cell(z, 'Cash', 'Amount'), const Money.rupees(4500));
      expect(cell(z, 'JazzCash', 'Amount'), const Money.rupees(3000));
      expect(cell(z, 'Total collected', 'Amount'), const Money.rupees(7500));
      expect(cell(z, 'Recovered', 'Amount'), const Money.rupees(2500));

      // One figure for the money in, whichever report is asked.
      final cashBookIn = cell(book, 'Closing balance', 'In')! as Money;
      final walletIn = cell(statement, 'Closing balance', 'Deposit')! as Money;
      expect(cashBookIn + walletIn, const Money.rupees(7500));
      expect(
        cell(z, 'Cash', 'Amount'),
        cashBookIn,
        reason: 'the Z report\'s cash is the drawer\'s',
      );
    });

    test('the CSV and Excel files carry each tender with its amount, and '
        'the same totals', () async {
      for (final kind in [
        ReportKind.saleReport,
        ReportKind.allTransactions,
        ReportKind.dayBook,
      ]) {
        final table = await run(kind);
        final csv = reportToCsv(table);
        expect(csv, contains(both), reason: '$kind csv');
        final sheet = readSpreadsheet(
          reportToXlsx(table, shopName: 'Chishti Kiryana Store'),
          fileName: 'report.xlsx',
        ).rows;
        expect(
          sheet.expand((r) => r),
          contains(contains(both)),
          reason: '$kind xlsx',
        );
      }
      final modes = await run(ReportKind.paymentModes);
      final rows = readSpreadsheet(
        reportToXlsx(modes, shopName: 'Chishti Kiryana Store'),
        fileName: 'modes.xlsx',
      ).rows;
      expect(
        rows.firstWhere((r) => r.isNotEmpty && r.first == 'Cash').sublist(2),
        ['3000.00', '1500.00', '4500.00'],
      );
      expect(
        rows
            .firstWhere((r) => r.isNotEmpty && r.first == 'JazzCash')
            .sublist(2),
        ['2000.00', '1000.00', '3000.00'],
      );
      expect(reportToCsv(modes), contains('Total,,7500.00,2500.00,7500.00'));
    });
  });
}
