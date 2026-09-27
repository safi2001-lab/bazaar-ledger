import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A shop registered for sales tax, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late TxRunner runner;
  late PostSaleUseCase sell;
  late String pcs;
  late String ghee;
  late String agency;

  const calculator = SaleCalculator(taxEngine: PakistanTaxEngine());

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
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    sell = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      calculator: calculator,
    );
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    await runner.run(actor, (tx) async {
      await tx.update('firms', firm.firmId, {'is_sales_tax_registered': 1});
      ghee = await tx.insert('items', {
        'name': 'Ghee 16kg tin',
        'name_search': 'ghee 16kg tin',
        'base_unit_id': pcs,
        'track_stock': 0,
      });
      agency = await tx.insert('parties', {
        'name': 'Bilal Store',
        'name_search': 'bilal store',
        'party_type': 'customer',
      });
    });
  });

  tearDown(() async => db.close());

  Future<PostedSale> ringGhee({String? to}) => sell(
    actor,
    SaleDraft(
      partyId: to,
      partyName: to == null ? null : 'Bilal Store',
      roundToRupee: false,
      lines: [
        SaleLineDraft(
          itemId: ghee,
          itemName: 'Ghee 16kg tin',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitCode: 'pcs',
          rate: Rate.rupees(10000),
          tracksStock: false,
        ),
      ],
    ),
  );

  Future<int> net(String key) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
                'AS n FROM journal_lines jl JOIN accounts a '
                "ON a.id = jl.account_id WHERE a.system_key = '$key'",
              )
              .getSingle())
          .read<int>('n');

  test(
    'a registered sale to an unregistered business owes both taxes',
    () async {
      final bill = await ringGhee(to: agency);
      expect(bill.total, const Money.rupees(12200));
      expect(await net('output_tax'), -180000);
      expect(await net('further_tax_payable'), -40000);
      expect(await net('sales'), -1000000);
      final taxes = await db
          .customSelect(
            'SELECT tax_code FROM document_line_taxes ORDER BY tax_code',
          )
          .get();
      expect(
        [for (final t in taxes) t.read<String>('tax_code')],
        ['FURTHER_4', 'ST_STD_18'],
      );
    },
  );

  test('prices that include tax credit sales without the tax', () async {
    await runner.run(actor, (tx) async {
      await tx.update('firms', firm.firmId, {'prices_include_tax': 1});
      // Active and registered, so no further tax on top.
      await tx.update('parties', agency, {
        'buyer_registration_type': 'registered',
        'is_on_atl': 1,
      });
    });
    final bill = await ringGhee(to: agency);
    expect(bill.total, const Money.rupees(10000));
    expect(await net('output_tax'), -152542);
    expect(await net('sales'), -847458);
  });

  test('a return gives back the tax on what came back', () async {
    final bill = await ringGhee(to: agency);
    final returns = RecordReturnUseCase(
      writer: DriftReturnWriter(runner: runner),
    );
    final sold = await DriftAppQueries(
      db,
    ).returnableLines(firm.firmId, bill.documentId);
    await returns(
      actor,
      ReturnDraft(
        originalDocumentId: bill.documentId,
        lines: [
          ReturnLineDraft(
            documentLineId: sold.single.documentLineId,
            qty: Qty.units(1),
          ),
        ],
        reason: 'Tin dented',
      ),
    );
    expect(await net('output_tax'), 0);
    expect(await net('further_tax_payable'), 0);
    expect(await net('accounts_receivable'), 0);

    final t = await ReportEngine(DriftReportSource(db)).run(
      ReportKind.salesTax,
      firmId: firm.firmId,
      period: ReportPeriod.day(actor.businessDate),
      today: actor.businessDate,
    );
    expect(t.totals.single.cells.last, Money.zero);
  });

  test('an unregistered shop charges no tax under the same pack', () async {
    await runner.run(actor, (tx) async {
      await tx.update('firms', firm.firmId, {'is_sales_tax_registered': 0});
    });
    final bill = await ringGhee(to: agency);
    expect(bill.total, const Money.rupees(10000));
    expect(await net('output_tax'), 0);
  });
}
