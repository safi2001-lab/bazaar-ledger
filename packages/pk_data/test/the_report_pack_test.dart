import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The report pack against a real database, after a day with a cash sale, a
/// sale on udhaar that was then voided, the rent paid from the drawer, and a
/// charge put on a khata.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  late ReportPeriod today;
  late TxRunner runner;
  late ActorContext actor;

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
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    final queries = DriftAppQueries(db);
    reports = ReportEngine(DriftReportSource(db));
    today = ReportPeriod.day(actor.businessDate);

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    late String oil;
    late String rashid;
    await runner.run(actor, (tx) async {
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      oil = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcs,
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(2000).inMilliPaisa,
      });
    });
    final cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');

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
    final udhaar = await sell(
      actor,
      SaleDraft(
        lines: [oilLine(1)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
      ),
    );
    await VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner))(
      actor,
      documentId: udhaar.documentId,
      reason: 'Rung by mistake',
    );
    await RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner))(
      actor,
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(1000),
        note: 'Shutter rent, September',
        paymentAccountId: cash.id,
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
  });

  tearDown(() async => db.close());

  Future<ReportTable> run(ReportKind kind) =>
      reports.run(kind, firmId: firm.firmId, period: today, today: today.from);

  Object? cell(ReportTable t, String first, [int column = 1]) =>
      t.rows.firstWhere((r) => r.cells.first == first).cells[column];

  test(
    'profit and loss ties to the postings, and a void earns nothing',
    () async {
      final t = await run(ReportKind.profitAndLoss);
      expect(cell(t, 'Net sales'), const Money.rupees(5000));
      expect(cell(t, 'Total cost of sales'), const Money.rupees(4000));
      expect(cell(t, 'Gross profit'), const Money.rupees(1000));
      expect(cell(t, 'Total other income'), const Money.rupees(500));
      expect(cell(t, 'Total expenses'), const Money.rupees(1000));
      expect(t.totals.single.cells.last, const Money.rupees(500));
    },
  );

  test('the cash book closes on the cash in the books', () async {
    final t = await run(ReportKind.cashBook);
    expect(t.rows.first.cells.last, Money.zero);
    expect(t.totals.single.cells.sublist(3), [
      const Money.rupees(5000),
      const Money.rupees(1000),
      const Money.rupees(4000),
    ]);
  });

  test('the day book lists every entry, the reversal included', () async {
    final t = await run(ReportKind.dayBook);
    expect(t.rows.where((r) => r.style == RowStyle.line), hasLength(5));
    expect(t.rows.where((r) => r.cells[2] == 'Reversal'), hasLength(1));
  });

  test('sales by item counts only bills that stand', () async {
    final t = await run(ReportKind.salesByItem);
    expect(t.rows.first.cells, [
      'Cooking Oil 5L',
      Qty.units(2),
      'pcs',
      const Money.rupees(5000),
      const Money.rupees(4000),
      const Money.rupees(1000),
      2000,
    ]);
  });

  test('expenses by head shows the rent', () async {
    final t = await run(ReportKind.expenses);
    expect(cell(t, 'Rent'), const Money.rupees(1000));
    expect(cell(t, 'Total'), const Money.rupees(1000));
  });

  test('stock value reads the shelf and the books', () async {
    final t = await run(ReportKind.stockValue);
    expect(t.rows.first.cells.sublist(0, 2), ['Cooking Oil 5L', Qty.units(-2)]);
    expect(t.totals.single.cells.last, const Money.rupees(-4000));
    expect(t.notes.first, 'Inventory in the books: Rs -4,000.00.');
  });

  test('sales by day counts the bill that stands', () async {
    final t = await run(ReportKind.salesByDay);
    expect(t.rows.first.cells, [
      '2026-09-26',
      1,
      const Money.rupees(5000),
      Money.zero,
      const Money.rupees(5000),
      Money.zero,
    ]);
  });

  test('udhaar by age owes what the khata says', () async {
    final t = await run(ReportKind.receivables);
    final rashid = t.rows.first;
    expect(rashid.cells.first, 'Rashid Traders');
    expect(rashid.cells[2], const Money.rupees(500), reason: '0-30 days');
    final id = (await db.customSelect('SELECT id FROM parties').getSingle())
        .read<String>('id');
    final party = await DriftAppQueries(db).partyById(firm.firmId, id);
    expect(rashid.cells.last, party!.balance);
  });

  test('owed to suppliers shows the bill left on account', () async {
    late String supplier;
    await runner.run(actor, (tx) async {
      supplier = await tx.insert('parties', {
        'name': 'Malik Property',
        'name_search': 'malik property',
        'party_type': 'supplier',
      });
    });
    await RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner))(
      actor,
      ExpenseDraft(
        accountSystemKey: 'utilities',
        amount: const Money.rupees(700),
        note: 'Bijli ka bill, on account',
        partyId: supplier,
      ),
    );

    final t = await run(ReportKind.payables);
    expect(t.rows.first.cells.first, 'Malik Property');
    expect(t.rows.first.cells[2], const Money.rupees(700));
    expect(t.totals.single.cells.last, const Money.rupees(700));
  });

  test('the trial balance agrees and the balance sheet balances', () async {
    final tb = await run(ReportKind.trialBalance);
    final sides = tb.totals.single.cells.sublist(2);
    expect(sides.first, sides.last);
    final bs = await run(ReportKind.balanceSheet);
    final assets = bs.rows
        .firstWhere((r) => r.cells.first == 'Total assets')
        .cells
        .last;
    expect(bs.totals.single.cells.last, assets);
    expect(bs.notes.first, startsWith('What the shop has equals'));
  });
}
