import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The transaction and party reports (M33) against a real database, and
/// each tied to the books: a sale report total to the day's sales, a party
/// statement's closing to the khata, a cash flow's drawer to the Cash Book.
///
/// The day: a cash sale to a walk-in; a bill on udhaar to Rashid Traders (a
/// wholesale customer), who pays part of it and brings one tin back; a bill
/// to Akbar paid by JazzCash; a bill rung by mistake and voided; rice
/// bought from Punjab Rice Mills, part paid; a charge on Rashid's khata;
/// the rent from the drawer.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  late DriftReportSource source;
  late DriftAppQueries queries;
  late ReportPeriod today;
  late String rashid;
  late String akbar;
  late String mill;
  late String oil;
  late String rice;
  late String rashidBill;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    source = DriftReportSource(db);
    reports = ReportEngine(source);
    today = ReportPeriod.day(actor.businessDate);

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    await runner.run(actor, (tx) async {
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
        'party_group': 'Wholesale',
      });
      akbar = await tx.insert('parties', {
        'name': 'Akbar',
        'name_search': 'akbar',
        'party_type': 'customer',
      });
      mill = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
      });
      oil = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcs,
        'category': 'Ghee and oil',
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(2000).inMilliPaisa,
      });
      rice = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcs,
        'category': 'Chawal',
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
      });
    });
    final accounts = await queries.paymentAccounts(firm.firmId);
    final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
    final jazz = accounts.firstWhere((a) => a.modeLabel == 'jazzcash');

    SaleLineDraft oilLine(int n) => SaleLineDraft(
      itemId: oil,
      itemName: 'Cooking Oil 5L',
      qty: Qty.units(n),
      baseQty: Qty.units(n),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(2500),
    );

    final sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    // A walk-in, cash: Rs 5,000.
    await sell(
      actor,
      SaleDraft(
        lines: [oilLine(2)],
        roundToRupee: false,
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(5000),
          ),
        ],
      ),
    );
    // Rashid, on udhaar: Rs 7,500.
    rashidBill = (await sell(
      actor,
      SaleDraft(
        lines: [oilLine(3)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
      ),
    )).documentId;
    // Akbar, Rs 1,000 of Rs 2,500 by JazzCash.
    await sell(
      actor,
      SaleDraft(
        lines: [oilLine(1)],
        partyId: akbar,
        partyName: 'Akbar',
        roundToRupee: false,
        tenders: [
          TenderDraft(
            paymentAccountId: jazz.id,
            mode: 'jazzcash',
            amount: const Money.rupees(1000),
          ),
        ],
      ),
    );
    // Rung by mistake and voided.
    final mistake = await sell(
      actor,
      SaleDraft(
        lines: [oilLine(1)],
        roundToRupee: false,
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(2500),
          ),
        ],
      ),
    );
    await VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner))(
      actor,
      documentId: mistake.documentId,
      reason: 'Rung by mistake',
    );
    // Rashid pays Rs 2,000 on his khata, then brings one tin back.
    await RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner))(
      actor,
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(2000),
        mode: 'cash',
        paymentAccountId: cash.id,
      ),
    );
    final line =
        (await db
                .customSelect(
                  'SELECT id FROM document_lines WHERE document_id = ?',
                  variables: [Variable<String>(rashidBill)],
                )
                .getSingle())
            .read<String>('id');
    await RecordReturnUseCase(writer: DriftReturnWriter(runner: runner))(
      actor,
      ReturnDraft(
        originalDocumentId: rashidBill,
        reason: 'Dabba pichka hua',
        lines: [ReturnLineDraft(documentLineId: line, qty: Qty.units(1))],
      ),
    );
    // Rice from the mill: Rs 1,200, Rs 200 paid at the door.
    await RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner))(
      actor,
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
    await RecordDebitNoteUseCase(writer: DriftDebitNoteWriter(runner: runner))(
      actor,
      DebitNoteDraft(
        partyId: rashid,
        amount: const Money.rupees(500),
        note: 'Bilty ka kiraya',
      ),
    );
    await RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner))(
      actor,
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(1000),
        note: 'Shutter rent',
        paymentAccountId: cash.id,
      ),
    );
  });

  tearDown(() async => db.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportFilters filters = ReportFilters.none,
  }) => reports.run(
    kind,
    firmId: firm.firmId,
    period: today,
    today: today.from,
    filters: filters,
  );

  Object? cell(ReportTable t, String first, [int column = 1]) =>
      t.rows.firstWhere((r) => r.cells.first == first).cells[column];

  group('sale report', () {
    test('every bill that stands, and its total is the day\'s sales', () async {
      final t = await run(ReportKind.saleReport);
      expect(t.rows.where((r) => r.style == RowStyle.line), hasLength(3));
      final byDay = await run(ReportKind.salesByDay);
      expect(t.summary.first.amount, byDay.totals.single.cells[2]);
      expect(t.summary.first.amount, const Money.rupees(15000));

      final rashidRow = t.rows.firstWhere(
        (r) => r.cells[2] == 'Rashid Traders',
      );
      expect(
        rashidRow.cells.sublist(3, 6),
        [
          const Money.rupees(7500),
          const Money.rupees(2000),
          const Money.rupees(3000),
        ],
        reason: 'paid 2,000, and the tin brought back came off',
      );
      expect(rashidRow.cells.last, 'Partly paid');
      expect(rashidRow.link?.id, rashidBill);
      final akbarRow = t.rows.firstWhere((r) => r.cells[2] == 'Akbar');
      expect(akbarRow.cells[6], 'JazzCash');
    });

    test('a narrowed sale report is narrowed in the query', () async {
      Future<int> bills(ReportFilters f) async => (await run(
        ReportKind.saleReport,
        filters: f,
      )).rows.where((r) => r.style == RowStyle.line).length;
      expect(await bills(ReportFilters(partyId: rashid)), 1);
      expect(await bills(const ReportFilters(partyGroup: 'Wholesale')), 1);
      expect(
        await bills(const ReportFilters(partyGroup: ReportFilters.ungrouped)),
        1,
        reason: 'Akbar; the walk-in has no party to be in a group',
      );
      expect(
        await bills(const ReportFilters(paymentStatus: PaymentStatus.paid)),
        1,
      );
      expect(
        await bills(const ReportFilters(paymentStatus: PaymentStatus.partial)),
        2,
      );
      expect(await bills(const ReportFilters(paymentMode: 'jazzcash')), 1);
      expect(await bills(ReportFilters(userId: firm.ownerUserId)), 3);
      expect(await bills(const ReportFilters(userId: 'nobody')), 0);
      expect(await bills(ReportFilters(itemId: rice)), 0);
      expect(await bills(const ReportFilters(category: 'Ghee and oil')), 3);
      final t = await run(
        ReportKind.saleReport,
        filters: ReportFilters(partyId: rashid, partyName: 'Rashid Traders'),
      );
      expect(t.filters, ['Party: Rashid Traders']);
    });
  });

  test(
    'the purchase report shows the delivery and what is still unpaid',
    () async {
      final t = await run(ReportKind.purchaseReport);
      expect(t.rows.first.cells.sublist(2, 6), [
        'Punjab Rice Mills',
        const Money.rupees(1200),
        const Money.rupees(200),
        const Money.rupees(1000),
      ]);
      expect(t.rows.first.cells.last, 'Partly paid');
    },
  );

  test(
    'bill-wise profit ties to sales by item and to profit by party',
    () async {
      final bills = await run(ReportKind.billWiseProfit);
      final items = await run(ReportKind.salesByItem);
      final parties = await run(ReportKind.partyProfitAndLoss);
      final profit = bills.totals.single.cells[5];
      expect(profit, items.totals.single.cells[5]);
      expect(profit, parties.totals.single.cells[3]);
      // Six tins sold, one back: five at Rs 500 over cost.
      expect(profit, const Money.rupees(2500));
      expect(cell(parties, 'Walk-in customers', 3), const Money.rupees(1000));
      expect(
        bills.rows.where((r) => '${r.cells[1]}'.endsWith('(return)')),
        hasLength(1),
      );
    },
  );

  test('all transactions lists every document and the receipt, the void '
      'shown, the counter\'s own tenders not', () async {
    final t = await run(ReportKind.allTransactions);
    final types = [
      for (final r in t.rows.where((r) => r.style == RowStyle.line)) r.cells[2],
    ];
    expect(types.where((t) => t == 'Sale'), hasLength(4));
    expect(types.where((t) => t == 'Payment in'), hasLength(1));
    expect(types, containsAll(['Sale return', 'Purchase', 'Charge']));
    expect(types, contains('Expense'));
    expect(t.rows.where((r) => r.cells.last == 'Void'), hasLength(1));

    final receipts = await run(
      ReportKind.allTransactions,
      filters: const ReportFilters(transactionType: TransactionType.paymentIn),
    );
    expect(receipts.summary.first.count, 1);
    expect(receipts.rows.first.cells[3], 'Rashid Traders');
  });

  test(
    'the day book shows what each entry moved, and the receipt\'s party',
    () async {
      final t = await run(ReportKind.dayBook);
      final receipt = t.rows.firstWhere((r) => r.cells[2] == 'Payment');
      expect(receipt.cells[3], 'Rashid Traders');
      expect(receipt.cells[6], const Money.rupees(2000));
      final udhaar = t.rows.firstWhere((r) => r.cells[1] == 'INV-2627-0002');
      expect(udhaar.cells[5], const Money.rupees(7500));
      expect(udhaar.cells[6], isNull, reason: 'udhaar moves no money');
      // In: 5,000 + 1,000 + 2,500 + 2,000. Out: the void's 2,500, the
      // door's 200 and the rent's 1,000.
      expect(t.totals.single.cells.sublist(6), [
        const Money.rupees(10500),
        const Money.rupees(3700),
      ]);
    },
  );

  test('the cash flow\'s drawer closes where the cash book does', () async {
    final flow = await run(ReportKind.cashflow);
    final book = await run(ReportKind.cashBook);
    expect(flow.totals.single.cells[1], book.totals.single.cells.last);
    expect(flow.totals.single.cells[2], const Money.rupees(1000));
    expect(cell(flow, 'Received on khatas'), const Money.rupees(2000));
    expect(cell(flow, 'Sales at the counter', 2), const Money.rupees(1000));
  });

  test('the trading account arrives at the books\' cost of goods sold, and '
      'the profit is unchanged', () async {
    final t = await run(ReportKind.profitAndLoss);
    final cogs = cell(t, 'Cost of goods sold');
    final balances = await source.accountMovements(firm.firmId, today);
    expect(cogs, balances.firstWhere((a) => a.systemKey == 'cogs').net);
    expect(cell(t, 'Purchases'), const Money.rupees(1200));
    // Net sales 12,500, cost 10,000, charge 500, rent 1,000.
    expect(t.totals.single.cells.last, const Money.rupees(2000));
  });

  group('party statement', () {
    test('closes on the khata\'s balance, the return included', () async {
      final t = await run(
        ReportKind.partyStatement,
        filters: ReportFilters(partyId: rashid),
      );
      final khata = await queries.partyById(firm.firmId, rashid);
      expect(t.totals.single.cells.last, khata!.balance);
      expect(khata.balance, const Money.rupees(3500));
      expect(t.rows.where((r) => r.cells[1] == 'Goods returned'), hasLength(1));
    });

    test('a supplier\'s closes on what the shop owes them', () async {
      final t = await run(
        ReportKind.partyStatement,
        filters: ReportFilters(partyId: mill),
      );
      final khata = await queries.partyById(firm.firmId, mill);
      expect(t.totals.single.cells.last, khata!.payable);
      expect(t.summary.last.label, 'We owe');
    });
  });

  test(
    'all parties shows the khata\'s balance each way for every party',
    () async {
      final t = await run(ReportKind.allParties);
      for (final row in t.rows.where((r) => r.link != null)) {
        final khata = await queries.partyById(firm.firmId, row.link!.id);
        expect(row.cells[4], khata!.balance, reason: '${row.cells.first}');
        expect(row.cells[5], khata.payable, reason: '${row.cells.first}');
      }
      expect(cell(t, 'Rashid Traders', 2), 'Wholesale');
      final grouped = await run(
        ReportKind.allParties,
        filters: const ReportFilters(partyGroup: 'Wholesale'),
      );
      expect(grouped.rows.where((r) => r.link != null), hasLength(1));
    },
  );

  test('a party\'s items, sold and bought, net of returns', () async {
    final t = await run(
      ReportKind.partyItems,
      filters: ReportFilters(partyId: rashid, partyName: 'Rashid Traders'),
    );
    expect(t.rows.first.cells.sublist(0, 4), [
      'Cooking Oil 5L',
      'pcs',
      Qty.units(2),
      const Money.rupees(5000),
    ]);
    final mills = await run(
      ReportKind.partyItems,
      filters: ReportFilters(partyId: mill),
    );
    expect(mills.rows.first.cells.sublist(4), [
      Qty.units(10),
      const Money.rupees(1200),
    ]);
  });

  test(
    'sale and purchase by party and by group, each net of returns',
    () async {
      final byParty = await run(ReportKind.salePurchaseByParty);
      expect(cell(byParty, 'Rashid Traders'), const Money.rupees(5000));
      expect(cell(byParty, 'Punjab Rice Mills', 2), const Money.rupees(1200));
      final byGroup = await run(ReportKind.salePurchaseByPartyGroup);
      expect(cell(byGroup, 'Wholesale', 2), const Money.rupees(5000));
      expect(cell(byGroup, 'Ungrouped', 1), 2, reason: 'Akbar and the mill');
      expect(cell(byGroup, 'Walk-in customers', 2), const Money.rupees(5000));
      expect(byGroup.totals.single.cells[2], byParty.totals.single.cells[1]);
    },
  );

  test('a filter offers what the shop has', () async {
    final groups = await source.choices(firm.firmId, ReportFilter.partyGroup);
    expect([for (final c in groups) c.label], ['Ungrouped', 'Wholesale']);
    final categories = await source.choices(
      firm.firmId,
      ReportFilter.itemCategory,
    );
    expect([for (final c in categories) c.label], ['Chawal', 'Ghee and oil']);
    final items = await source.choices(
      firm.firmId,
      ReportFilter.item,
      query: 'chawal',
    );
    expect(items.single.id, rice);
    final staff = await source.choices(firm.firmId, ReportFilter.user);
    expect(staff.single.label, 'Malik Sahib');
  });
}
