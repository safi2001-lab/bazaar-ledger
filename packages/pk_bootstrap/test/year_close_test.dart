import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_data/pk_data.dart' show Variable;

/// Closing a year into retained earnings, and the shop's own accounts (M26).
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 5, 10, 6));
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
  });

  tearDown(() => shop.close());

  Future<void> sellFor(int rupees) async {
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    final item = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Item $rupees ${clock.nowUtc().millisecondsSinceEpoch}',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(rupees),
      ),
    );
    await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: item,
            itemName: 'Item',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: Money.rupees(rupees),
          ),
        ],
      ),
    );
  }

  Future<void> spend(int rupees) => shop.recordExpense(
    shop.actorNow(),
    ExpenseDraft(
      accountSystemKey: 'rent',
      amount: Money.rupees(rupees),
      note: 'Dukaan ka kiraya',
      paymentAccountId: cash,
    ),
  );

  Future<ReportTable> run(ReportKind kind, ReportPeriod period) =>
      shop.reports.run(
        kind,
        firmId: firmId,
        period: period,
        today: BusinessDate.now(clock),
      );

  Object? row(ReportTable t, String first, [int column = 1]) =>
      t.rows.where((r) => r.cells.first == first).firstOrNull?.cells[column];

  final year2526 = ReportPeriod(
    const BusinessDate('2025-07-01'),
    const BusinessDate('2026-06-30'),
  );

  group('year close', () {
    test('the year\'s profit moves into retained earnings, and the year '
        'still reads as it was', () async {
      await sellFor(10000);
      await spend(3000);
      clock.set(DateTime.utc(2026, 7, 2, 6));

      final closed = await shop.closeYear(2526);
      expect(closed.entryNo, isNotEmpty);

      final pl = await run(ReportKind.profitAndLoss, year2526);
      expect(
        row(pl, 'Net profit'),
        const Money.rupees(7000),
        reason: 'the closed year still shows what it made',
      );
      final sheet = await run(
        ReportKind.balanceSheet,
        ReportPeriod.day(BusinessDate.now(clock)),
      );
      expect(row(sheet, 'Retained Earnings'), const Money.rupees(7000));
      expect(row(sheet, 'Profit to date'), Money.zero);
      final trial = await run(
        ReportKind.trialBalance,
        ReportPeriod.day(BusinessDate.now(clock)),
      );
      final totals = trial.rows.last.cells;
      expect(totals[totals.length - 2], totals.last);
    });

    test('a year cannot be closed before it ends, nor twice', () async {
      await sellFor(5000);
      await expectLater(shop.closeYear(2526), throwsA(isA<YearCloseRefused>()));
      clock.set(DateTime.utc(2026, 7, 1, 6));
      await shop.closeYear(2526);
      await expectLater(shop.closeYear(2526), throwsA(isA<YearCloseRefused>()));
    });

    test('a bill entered late for June is closed by closing again', () async {
      await sellFor(5000);
      clock.set(DateTime.utc(2026, 7, 1, 6));
      await shop.closeYear(2526);
      // The June bill found under the counter, entered with June's date.
      clock.set(DateTime.utc(2026, 6, 30, 6));
      await sellFor(1000);
      clock.set(DateTime.utc(2026, 7, 3, 6));
      await shop.closeYear(2526);
      final sheet = await run(
        ReportKind.balanceSheet,
        ReportPeriod.day(BusinessDate.now(clock)),
      );
      expect(row(sheet, 'Retained Earnings'), const Money.rupees(6000));
    });
  });

  group('accounts of the shop\'s own', () {
    test('an expense head is added after the last one, and can be spent '
        'against', () async {
      final id = await shop.addAccount(
        name: 'Generator diesel',
        type: 'expense',
      );
      final chart = await shop.database
          .customSelect(
            'SELECT code, normal_side FROM accounts WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingle();
      expect(int.parse(chart.read<String>('code')), greaterThan(5000));
      expect(chart.read<String>('normal_side'), 'debit');
      await expectLater(
        shop.addAccount(name: 'generator DIESEL', type: 'expense'),
        throwsA(isA<YearCloseRefused>()),
      );
      await expectLater(
        shop.addAccount(name: '  ', type: 'expense'),
        throwsA(isA<YearCloseRefused>()),
      );
    });
  });
}
