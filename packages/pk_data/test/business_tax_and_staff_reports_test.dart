import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The business status, staff and time, tax, expense and order reports and
/// the night's Z report (M35), against a real database, each tied to the
/// books: a bank statement closes on the account's balance, the tax report's
/// output tax is the sales tax report's total, the payment-mode summary
/// collects what the cash flow says came in, and the Z report's sales are
/// the day's sale report.
///
/// A sales-tax-registered shop in Lahore, the 26th of September 2026, at a
/// quarter past two in the afternoon, Pakistan time:
///
///  * 1 August: Akbar (unregistered) takes rice on udhaar.
///  * 20 August: Rashid Traders (registered, 15 days' credit) takes rice
///    on udhaar.
///  * 25 September: Bilal, the cashier, rings a bill on the second counter
///    and voids it.
///  * Today: a walk-in pays cash; Bilal rings Rashid three tins at 10% off,
///    paid part in cash, part by JazzCash, the rest on udhaar; Rashid
///    brings a tin back; Akbar pays his August bill in cash and Rashid pays
///    Rs 1,000 by bank; rice comes in from Punjab Rice Mills; rent, a
///    bijli bill from the bank and another left on account; two challans
///    to Akbar, one billed; a quotation to Rashid; the drawer is closed
///    Rs 100 short.
///  * Half past one that night, the 27th by the shop's clock: one more
///    cash sale.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  late DriftReportSource source;
  late String rashid;
  late String akbar;
  late String mill;
  late String bilal;
  late String rashidBill;
  late String voidedBill;
  late String quotation;
  late String openChallan;
  late String billedChallan;
  late String wallet;
  late String bank;

  const today = BusinessDate('2026-09-26');
  final day = ReportPeriod.day(today);
  final september = ReportPeriod.monthOf(today);
  final sinceAugust = ReportPeriod(const BusinessDate('2026-08-01'), today);

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Traders',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final owner = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    source = DriftReportSource(db);
    reports = ReportEngine(source);
    final queries = DriftAppQueries(db);

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    late String oil;
    late String rice;
    late String counter2;
    await runner.run(owner, (tx) async {
      await tx.update('firms', firm.firmId, {'is_sales_tax_registered': 1});
      bilal = await tx.insert('users', {'name': 'Bilal', 'role': 'cashier'});
      counter2 = await tx.insert('devices', {
        'label': 'Counter 2',
        'platform': 'test',
        'device_role': 'counter',
        'doc_prefix': 'B',
        'is_this_device': 0,
      });
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
        'party_group': 'Wholesale',
        'buyer_registration_type': 'registered',
        'is_on_atl': 1,
        'ntn': '1234567-8',
        'province': 'sindh',
        'phone': '0300 4471203',
        'credit_days': 15,
      });
      akbar = await tx.insert('parties', {
        'name': 'Akbar',
        'name_search': 'akbar',
        'party_type': 'customer',
        'cnic': '35202-1234567-1',
      });
      mill = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
        'buyer_registration_type': 'registered',
        'ntn': '7654321-0',
      });
      oil = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcs,
        'hs_code': '1514.1900',
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(2000).inMilliPaisa,
      });
      rice = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcs,
        'hs_code': '10063090',
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(120).inMilliPaisa,
      });
    });
    final accounts = await queries.paymentAccounts(firm.firmId);
    final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
    final jazz = accounts.firstWhere((a) => a.modeLabel == 'jazzcash');
    final bankAccount = accounts.firstWhere(
      (a) => a.modeLabel == 'bank_transfer',
    );
    Future<String> ledger(String key) async =>
        (await db
                .customSelect(
                  'SELECT id FROM accounts WHERE system_key = ?',
                  variables: [Variable<String>(key)],
                )
                .getSingle())
            .read<String>('id');
    wallet = await ledger('wallet');
    bank = await ledger('bank');

    final sell = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      calculator: const SaleCalculator(taxEngine: PakistanTaxEngine()),
    );
    SaleLineDraft oilLine(int n, {int discountBp = 0}) => SaleLineDraft(
      itemId: oil,
      itemName: 'Cooking Oil 5L',
      hsCode: '1514.1900',
      qty: Qty.units(n),
      baseQty: Qty.units(n),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(2500),
      discountBp: discountBp,
    );
    SaleLineDraft riceLine(int n) => SaleLineDraft(
      itemId: rice,
      itemName: 'Chawal Basmati',
      qty: Qty.units(n),
      baseQty: Qty.units(n),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(150),
    );
    TenderDraft tender(String mode, String account, int rupees) => TenderDraft(
      paymentAccountId: account,
      mode: mode,
      amount: Money.rupees(rupees),
    );
    ActorContext at(DateTime instant, {String? user, String? device}) =>
        ActorContext(
          firmId: firm.firmId,
          userId: user ?? firm.ownerUserId,
          deviceId: device ?? firm.deviceId,
          startedAtUtc: instant,
        );

    // 1 August: Akbar, Rs 1,500 of rice and both taxes, Rs 1,830 owed.
    await sell(
      at(DateTime.utc(2026, 8, 1, 6)),
      SaleDraft(
        lines: [riceLine(10)],
        partyId: akbar,
        partyName: 'Akbar',
        roundToRupee: false,
      ),
    );
    // 20 August: Rashid, Rs 1,500 of rice and sales tax, Rs 1,770 owed.
    await sell(
      at(DateTime.utc(2026, 8, 20, 6)),
      SaleDraft(
        lines: [riceLine(10)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
      ),
    );
    // 25 September: Bilal on the second counter, rung and voided.
    final yesterday = at(
      DateTime.utc(2026, 9, 25, 7),
      user: bilal,
      device: counter2,
    );
    voidedBill = (await sell(
      yesterday,
      SaleDraft(
        lines: [oilLine(1)],
        roundToRupee: false,
        tenders: [tender('cash', cash.id, 2950)],
      ),
    )).documentId;
    await VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner))(
      yesterday,
      documentId: voidedBill,
      reason: 'Rung by mistake',
    );

    // Today. A walk-in: Rs 5,000 and Rs 900 sales tax, cash.
    await sell(
      owner,
      SaleDraft(
        lines: [oilLine(2)],
        roundToRupee: false,
        tenders: [tender('cash', cash.id, 5900)],
      ),
    );
    // Bilal, on the second counter: Rashid, three tins at 10% off: Rs 6,750
    // and Rs 1,215 tax, Rs 7,965; Rs 3,000 cash and Rs 1,000 by JazzCash.
    rashidBill = (await sell(
      at(clock.nowUtc(), user: bilal, device: counter2),
      SaleDraft(
        lines: [oilLine(3, discountBp: 1000)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
        tenders: [
          tender('cash', cash.id, 3000),
          tender('jazzcash', jazz.id, 1000),
        ],
      ),
    )).documentId;
    final line =
        (await db
                .customSelect(
                  'SELECT id FROM document_lines WHERE document_id = ?',
                  variables: [Variable<String>(rashidBill)],
                )
                .getSingle())
            .read<String>('id');
    await RecordReturnUseCase(writer: DriftReturnWriter(runner: runner))(
      owner,
      ReturnDraft(
        originalDocumentId: rashidBill,
        reason: 'Dabba pichka hua',
        lines: [ReturnLineDraft(documentLineId: line, qty: Qty.units(1))],
      ),
    );
    final receive = RecordReceiptUseCase(
      writer: DriftPaymentWriter(runner: runner),
    );
    await receive(
      owner,
      ReceiptDraft(
        partyId: akbar,
        amount: const Money.rupees(1830),
        mode: 'cash',
        paymentAccountId: cash.id,
      ),
    );
    await receive(
      owner,
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(1000),
        mode: 'bank_transfer',
        paymentAccountId: bankAccount.id,
      ),
    );
    await RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner))(
      owner,
      PurchaseDraft(
        partyId: mill,
        supplierBillNo: 'PRM/771',
        paid: const Money.rupees(200),
        paymentAccountId: cash.id,
        lines: [
          PurchaseLineDraft(
            itemId: rice,
            itemName: 'Chawal Basmati',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(120),
          ),
        ],
      ),
    );
    final spend = RecordExpenseUseCase(
      writer: DriftExpenseWriter(runner: runner),
    );
    await spend(
      owner,
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(1000),
        note: 'Shutter rent',
        paymentAccountId: cash.id,
      ),
    );
    await spend(
      owner,
      ExpenseDraft(
        accountSystemKey: 'utilities',
        amount: const Money.rupees(400),
        note: 'Bijli bill',
        paymentAccountId: bankAccount.id,
      ),
    );
    await spend(
      owner,
      ExpenseDraft(
        accountSystemKey: 'utilities',
        amount: const Money.rupees(600),
        note: 'bijli  bill.',
        partyId: mill,
      ),
    );
    final send = IssueChallanUseCase(
      writer: DriftChallanWriter(runner: runner),
    );
    SaleDraft toAkbar(int tins, {String? from}) => SaleDraft(
      lines: [oilLine(tins)],
      partyId: akbar,
      partyName: 'Akbar',
      roundToRupee: false,
      convertedFromId: from,
    );
    billedChallan = (await send(owner, toAkbar(1))).id;
    openChallan = (await send(owner, toAkbar(2))).id;
    await sell(owner, toAkbar(1, from: billedChallan));
    quotation =
        (await SaveQuotationUseCase(
              writer: DriftQuotationWriter(runner: runner),
            )(
              owner,
              SaleDraft(
                lines: [riceLine(20)],
                partyId: rashid,
                partyName: 'Rashid Traders',
                roundToRupee: false,
              ),
            ))
            .id;
    final drawer = await queries.cashInDrawer(firm.firmId);
    await CloseDayUseCase(writer: DriftDayCloseWriter(runner: runner))(
      owner,
      counted: drawer - const Money.rupees(100),
    );

    // Half past one that night: the 27th by the shop's own clock.
    await sell(
      at(DateTime.utc(2026, 9, 26, 20, 30)),
      SaleDraft(
        lines: [riceLine(1)],
        roundToRupee: false,
        tenders: [tender('cash', cash.id, 177)],
      ),
    );
  });

  tearDown(() async => db.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportPeriod? period,
    ReportFilters filters = ReportFilters.none,
  }) => reports.run(
    kind,
    firmId: firm.firmId,
    period: period ?? day,
    today: today,
    filters: filters,
  );

  Object? cell(ReportTable t, String first, [int column = 1]) =>
      t.rows.firstWhere((r) => r.cells.first == first).cells[column];

  List<ReportRow> lines(ReportTable t) =>
      t.rows.where((r) => r.style == RowStyle.line).toList();

  /// What the tin that came back is worth in the books, before tax: the
  /// return's own figure, whatever the return writer valued it at.
  Future<Money> returned() async => Money.paisa(
    (await db
            .customSelect(
              "SELECT taxable_paisa FROM documents WHERE doc_type = 'sale_return'",
            )
            .getSingle())
        .read<int>('taxable_paisa'),
  );

  Money total(ReportTable t, String label) =>
      t.summary.firstWhere((f) => f.label == label).amount!;

  group('business status', () {
    test('the bank statement closes on the account\'s balance in the books, '
        'and every bank and wallet is a section of its own', () async {
      final balances = {
        for (final a in await source.accountBalances(firm.firmId, today))
          a.code: a.net,
      };
      Future<Money> balanceOf(String id) async {
        final code =
            (await db
                    .customSelect(
                      'SELECT code FROM accounts WHERE id = ?',
                      variables: [Variable<String>(id)],
                    )
                    .getSingle())
                .read<String>('code');
        return balances[code]!;
      }

      final wallets = await run(
        ReportKind.bankStatement,
        period: september,
        filters: ReportFilters(accountId: wallet, accountName: 'Wallets'),
      );
      expect(wallets.totals.single.cells.last, await balanceOf(wallet));
      expect(wallets.totals.single.cells.last, const Money.rupees(1000));
      expect(wallets.filters, ['Account: Wallets']);

      final banks = await run(
        ReportKind.bankStatement,
        period: september,
        filters: ReportFilters(accountId: bank),
      );
      expect(banks.totals.single.cells.last, await balanceOf(bank));
      final receipt = lines(
        banks,
      ).firstWhere((r) => r.cells[4] == const Money.rupees(1000));
      expect(receipt.cells[2], 'Rashid Traders');
      expect(
        lines(banks).any((r) => r.cells[3] == const Money.rupees(400)),
        isTrue,
        reason: 'the bijli bill paid from the bank',
      );

      final all = await run(ReportKind.bankStatement, period: september);
      expect(
        all.rows.where((r) => r.style == RowStyle.heading),
        hasLength(2),
        reason: 'the bank and the wallets; the drawer is the Cash Book',
      );
      expect(
        all.totals.single.cells.last,
        await balanceOf(wallet) + await balanceOf(bank),
      );
    });

    test('discount by party and by cashier: Bilal gave Rashid 10%', () async {
      final byParty = await run(ReportKind.discountByParty);
      expect(lines(byParty).single.cells.sublist(0, 5), [
        'Rashid Traders',
        1,
        const Money.rupees(7500),
        const Money.rupees(750),
        1000,
      ]);
      final byCashier = await run(ReportKind.discountByCashier);
      expect(lines(byCashier).first.cells.first, 'Bilal');
      expect(lines(byCashier).first.cells.last, 1000);
      expect(cell(byCashier, 'Total', 5), const Money.rupees(750));
    });

    test('how customers pay: Akbar paid his August bill 56 days late; '
        'Rashid\'s is overdue and he is a defaulter', () async {
      final t = await run(ReportKind.paymentPerformance, period: sinceAugust);
      final byName = {for (final r in lines(t)) r.cells.first: r.cells};
      expect(byName['Akbar']!.sublist(1, 9), [
        30,
        2,
        1,
        56,
        1,
        0,
        Money.zero,
        const Money.rupees(3050),
      ]);
      expect(byName['Rashid Traders']!.sublist(1, 8), [
        15,
        2,
        0,
        null,
        0,
        1,
        const Money.rupees(770),
      ]);
      expect(lines(t).first.cells.first, 'Rashid Traders');

      final defaulters = await run(ReportKind.defaulters);
      expect(lines(defaulters), hasLength(1));
      expect(lines(defaulters).single.cells, [
        'Rashid Traders',
        '0300 4471203',
        15,
        '2026-08-20',
        22,
        1,
        const Money.rupees(770),
        lines(defaulters).single.cells[7],
        null,
        '2026-09-26',
      ]);
      expect(lines(defaulters).single.link?.id, rashid);
      expect(
        await run(
          ReportKind.defaulters,
          filters: const ReportFilters(partyGroup: ReportFilters.ungrouped),
        ).then(lines),
        isEmpty,
      );
    });
  });

  group('staff and time', () {
    test('sales by cashier and by counter: every bill, void and return for '
        'whoever made it', () async {
      final t = await run(ReportKind.salesByCashier, period: september);
      final malik = lines(t).firstWhere((r) => r.cells.first == 'Malik Sahib');
      final bilalRow = lines(t).firstWhere((r) => r.cells.first == 'Bilal');
      expect(bilalRow.cells.sublist(1, 4), [
        'cashier',
        1,
        const Money.rupees(7965),
      ]);
      expect(bilalRow.cells.sublist(8, 10), [1, const Money.rupees(2950)]);
      expect(malik.cells[2], 3, reason: 'the walk-in, Akbar, and that night');
      expect(malik.cells[6], 1, reason: 'he took the tin back');

      final counters = await run(ReportKind.salesByCounter, period: september);
      expect(cell(counters, 'Counter 2', 1), 'B');
      expect(cell(counters, 'Counter 2', 8), 1);
      final onlyBilal = await run(
        ReportKind.salesByCounter,
        period: september,
        filters: ReportFilters(userId: bilal),
      );
      expect(lines(onlyBilal).single.cells.first, 'Counter 2');
    });

    test('the payment-mode summary counts each tender of a split bill on '
        'its own line, adds up to the sales, and collects what the cash flow '
        'says came in', () async {
      final t = await run(ReportKind.paymentModes);
      expect(lines(t).map((r) => r.cells.first), [
        'Cash',
        'Bank',
        'JazzCash',
        'Udhaar',
      ]);
      expect(cell(t, 'Cash', 2), const Money.rupees(8900));
      expect(cell(t, 'Cash', 3), const Money.rupees(1830));
      expect(cell(t, 'JazzCash', 2), const Money.rupees(1000));
      expect(cell(t, 'Bank', 3), const Money.rupees(1000));
      expect(cell(t, 'Udhaar', 2), const Money.rupees(7015));

      final sales = await run(ReportKind.saleReport);
      expect(cell(t, 'Total', 2), total(sales, 'Total sale'));

      final flow = await run(ReportKind.cashflow);
      expect(cell(t, 'Total', 4), total(flow, 'Money in'));
      expect(cell(t, 'Total', 4), const Money.rupees(12730));
    });

    test('hourly sales are on Pakistan time: the afternoon\'s bills at two, '
        'and half past one that night on the next day', () async {
      final t = await run(ReportKind.hourlySales);
      expect(lines(t).single.cells.sublist(0, 2), ['14:00-15:00', 3]);
      final night = await run(
        ReportKind.hourlySales,
        period: ReportPeriod.day(today.addDays(1)),
      );
      expect(lines(night).single.cells.sublist(0, 3), [
        '01:00-02:00',
        1,
        const Money.rupees(177),
      ]);
    });

    test('the Z report\'s sales are the day\'s sale report, its money the '
        'payment-mode summary, and its drawer the day close', () async {
      final z = await run(ReportKind.dailySummary);
      final sales = await run(ReportKind.saleReport);
      expect(cell(z, 'Sales, 3 bills'), total(sales, 'Total sale'));
      final modes = await run(ReportKind.paymentModes);
      expect(cell(z, 'Total collected'), cell(modes, 'Total', 4));
      expect(cell(z, 'Given, 2 bills'), const Money.rupees(7015));
      expect(cell(z, 'Recovered'), const Money.rupees(2830));
      expect(cell(z, 'Expenses, 3 vouchers'), const Money.rupees(2000));
      expect(cell(z, 'Short'), const Money.rupees(100));
      expect(z.rows.any((r) => r.cells.first == 'Gross profit'), isTrue);

      final cashier = await ReportEngine(source, canSeeCosts: false).run(
        ReportKind.dailySummary,
        firmId: firm.firmId,
        period: day,
        today: today,
      );
      expect(cashier.rows.any((r) => r.cells.first == 'Gross profit'), isFalse);
    });

    test('changed and cancelled bills say who voided what, and why', () async {
      final t = await run(ReportKind.changedBills, period: september);
      final voided = lines(t).firstWhere((r) => r.cells[2] == 'Voided');
      expect(voided.cells.sublist(0, 1), ['2026-09-25']);
      expect(voided.cells.sublist(5), [
        const Money.rupees(2950),
        'Bilal',
        'Rung by mistake',
      ]);
      expect(voided.link?.id, voidedBill);
      final returned = lines(t).firstWhere((r) => r.cells[2] == 'Sale return');
      expect(returned.cells[1], '14:15', reason: 'Pakistan time');
      expect(returned.cells[4], 'Rashid Traders');
      expect(returned.cells.last, 'Dabba pichka hua');
      final byBilal = await run(
        ReportKind.changedBills,
        period: september,
        filters: ReportFilters(userId: bilal),
      );
      expect(lines(byBilal), hasLength(1));
    });
  });

  group('taxes', () {
    test('the tax report\'s output tax is the sales tax report\'s total, '
        'party by party with the NTN', () async {
      final t = await run(ReportKind.taxReport, period: september);
      final summary = await run(ReportKind.salesTax, period: september);
      expect(cell(t, 'Total', 4), summary.totals.single.cells.last);
      expect(cell(t, 'Rashid Traders', 1), '1234567-8');
      expect(
        cell(t, 'Akbar', 4),
        const Money.rupees(550),
        reason: 'Rs 450 sales tax and Rs 100 further tax on the challan bill',
      );
      final rateReport = await run(ReportKind.taxRateReport, period: september);
      expect(rateReport.totals.single.cells.last, cell(t, 'Total', 4));
      expect(cell(rateReport, 'Further tax', 4), const Money.rupees(100));
      final back = rateReport.rows.skipWhile(
        (r) => r.cells.first != 'Given back on returns',
      );
      expect(
        back.elementAt(1).cells.sublist(0, 3),
        ['Standard rate', 1800, -1],
        reason: 'the tin went back at the rate it was sold at',
      );
      final narrowed = await run(
        ReportKind.taxReport,
        period: september,
        filters: ReportFilters(partyId: akbar),
      );
      expect(lines(narrowed).single.cells.first, 'Akbar');
    });

    test('sales by HS code, net of the tin that came back', () async {
      final t = await run(ReportKind.salesByHsCode, period: september);
      expect(lines(t).map((r) => r.cells.first), ['1514.1900', '10063090']);
      expect(
        cell(t, '1514.1900', 4),
        const Money.rupees(5000 + 6750 + 2500) - await returned(),
      );
    });

    test('Annex-C is a row per line in FBR\'s columns, and Annex-A the '
        'deliveries under the supplier\'s own number', () async {
      final c = await run(ReportKind.annexC, period: september);
      final rows = lines(c);
      expect(rows, hasLength(5), reason: 'not the voided bill');
      final rashidRow = rows.firstWhere(
        (r) => r.cells[1] == 'Rashid Traders' && r.cells[5] == 'Sale Invoice',
      );
      expect(rashidRow.cells.sublist(0, 11), [
        '1234567-8',
        'Rashid Traders',
        'Registered',
        'PUNJAB',
        'SINDH',
        'Sale Invoice',
        rashidRow.cells[6],
        '26-Sep-2026',
        '1514.1900:-',
        'Goods at standard rate (default)',
        1800,
      ]);
      expect(rashidRow.cells.sublist(12, 16), [
        Qty.units(3),
        'Numbers, pieces, units',
        const Money.rupees(6750),
        const Money.rupees(1215),
      ]);
      final credit = rows.firstWhere((r) => r.cells[5] == 'Credit Note');
      expect(credit.cells[14], await returned());
      expect(credit.cells.sublist(9, 11), [
        'Goods at standard rate (default)',
        1800,
      ], reason: 'on the footing of the sale it returns');
      expect(credit.cells[23], rashidRow.cells[6], reason: 'the bill returned');
      expect(credit.cells[25], 'Dabba pichka hua');
      final akbarRow = rows.firstWhere((r) => r.cells[1] == 'Akbar');
      expect(akbarRow.cells.sublist(0, 3), [
        '3520212345671',
        'Akbar',
        'Unregistered',
      ]);
      expect(akbarRow.cells[18], const Money.rupees(100), reason: 'further');
      final night = rows.firstWhere((r) => r.cells[7] == '27-Sep-2026');
      expect(night.cells.sublist(1, 3), [
        'Walk-in customer',
        'Retail Consumer',
      ]);
      expect(night.cells[8], '1006.3090:-');

      final a = await run(ReportKind.annexA, period: september);
      expect(lines(a).single.cells.sublist(0, 8), [
        '7654321-0',
        'Punjab Rice Mills',
        'Registered',
        'PUNJAB',
        'PUNJAB',
        'Purchase Invoice',
        'PRM/771',
        '26-Sep-2026',
      ]);
      expect(lines(a).single.cells[14], const Money.rupees(1200));
    });
  });

  group('expenses', () {
    test('every voucher with its head and where it was paid from, narrowed '
        'by head, by mode and by who', () async {
      final t = await run(ReportKind.expenseTransactions);
      expect(lines(t).map((r) => [r.cells[3], r.cells[4], r.cells[5]]), [
        ['Rent', 'Golak', const Money.rupees(1000)],
        ['Utilities', 'Bank', const Money.rupees(400)],
        ['Utilities', 'On account', const Money.rupees(600)],
      ]);
      expect(lines(t).last.cells[2], 'Punjab Rice Mills');
      final heads = await source.choices(
        firm.firmId,
        ReportFilter.expenseHead,
        query: 'util',
      );
      final utilities = heads.single;
      Future<int> count(ReportFilters f) async =>
          lines(await run(ReportKind.expenseTransactions, filters: f)).length;
      expect(
        await count(
          ReportFilters(
            expenseHeadId: utilities.id,
            expenseHeadName: utilities.label,
          ),
        ),
        2,
      );
      expect(await count(const ReportFilters(paymentMode: 'bank_transfer')), 1);
      expect(await count(const ReportFilters(paymentMode: 'cash')), 1);
      expect(await count(ReportFilters(userId: bilal)), 0);
    });

    test(
      'by head and by what it was for, both adding up to the vouchers',
      () async {
        final heads = await run(ReportKind.expenseCategories);
        expect(cell(heads, 'Utilities', 1), 2);
        expect(heads.totals.single.cells[2], const Money.rupees(2000));
        final items = await run(ReportKind.expenseItems);
        final bijli = lines(
          items,
        ).firstWhere((r) => r.cells.first == 'Utilities');
        expect(bijli.cells.sublist(2, 4), [2, const Money.rupees(1000)]);
        expect(items.totals.single.cells[3], const Money.rupees(2000));
      },
    );
  });

  group('orders', () {
    test('the quotation and the challan not yet billed are open; the billed '
        'challan is not', () async {
      final quotes = await run(ReportKind.openQuotations);
      expect(lines(quotes).single.link?.id, quotation);
      expect(lines(quotes).single.cells.sublist(2, 6), [
        'Rashid Traders',
        1,
        lines(quotes).single.cells[4],
        0,
      ]);
      final challans = await run(ReportKind.openChallans);
      expect(lines(challans).map((r) => r.link?.id), [openChallan]);
      expect(
        lines(challans).map((r) => r.link?.id),
        isNot(contains(billedChallan)),
      );
      final items = await run(ReportKind.openOrderItems);
      final byItem = {for (final r in lines(items)) r.cells.first: r.cells};
      expect(byItem['Cooking Oil 5L']!.sublist(1, 3), [
        'Challans',
        Qty.units(2),
      ]);
      expect(byItem['Chawal Basmati']!.sublist(1, 3), [
        'Quotations',
        Qty.units(20),
      ]);
      expect(
        lines(
          await run(
            ReportKind.openQuotations,
            filters: ReportFilters(partyId: akbar),
          ),
        ),
        isEmpty,
      );
    });
  });

  test(
    'a money account and an expense head are offered from the chart',
    () async {
      final money = await source.choices(
        firm.firmId,
        ReportFilter.moneyAccount,
      );
      expect(money.map((c) => c.id), containsAll([wallet, bank]));
      expect(
        money.firstWhere((c) => c.id == wallet).detail,
        allOf(contains('JazzCash'), contains('EasyPaisa')),
      );
      final heads = await source.choices(firm.firmId, ReportFilter.expenseHead);
      expect(heads.map((c) => c.label), contains('Rent'));
      expect(
        heads.map((c) => c.label).join(' '),
        isNot(contains('Cost of Goods')),
      );
    },
  );
}
