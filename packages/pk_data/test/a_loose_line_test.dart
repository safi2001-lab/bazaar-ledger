import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A line with no item behind it (M37), through the real write path.
///
/// The schema has allowed `document_lines.item_id` to be null since v1; this
/// is the first thing to write one. What has to hold: the row lands with no
/// item and no cost, no stock row is written for it, the books balance, the
/// receipt carries it, and it comes back — or is cancelled — as money only.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordReturnUseCase takeBack;
  late VoidDocumentUseCase voidDocument;
  late ActorContext actor;
  late String pcs;
  late String oil;
  late String rashid;
  late String cash;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 2, 6));
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
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    takeBack = RecordReturnUseCase(writer: DriftReturnWriter(runner: runner));
    voidDocument = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));
    pcs =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;
    await runner.run(actor, (tx) async {
      oil = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcs,
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(2100).inMilliPaisa,
      });
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
    });
  });

  tearDown(() async => db.close());

  /// A tin of oil and two and a half kilos of loose onions at Rs 120.
  Future<PostedSale> sell({String? partyId}) => postSale(
    actor,
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.one,
          baseQty: Qty.one,
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(2500),
        ),
        SaleLineDraft(
          itemId: null,
          itemName: 'Pyaz',
          qty: Qty.parse('2.500'),
          baseQty: Qty.parse('2.500'),
          unitCode: 'kg',
          rate: Rate.rupees(120),
          tracksStock: false,
        ),
      ],
      tenders: partyId != null
          ? const []
          : [
              TenderDraft(
                paymentAccountId: cash,
                mode: 'cash',
                amount: const Money.rupees(2800),
              ),
            ],
    ),
  );

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  Future<int> total(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  /// Every account summed: what was debited less what was credited.
  Future<int> outOfBalance() => total(
    'SELECT COALESCE(SUM(debit_paisa) - SUM(credit_paisa), 0) AS n '
    'FROM journal_lines',
  );

  Future<int> accountNet(String key) => total(
    'SELECT COALESCE(SUM(jl.credit_paisa - jl.debit_paisa), 0) AS n '
    'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
    "WHERE a.system_key = '$key'",
  );

  group('a loose line', () {
    test(
      'sells with no item, no stock and no cost, and the books balance',
      () async {
        final sale = await sell();
        expect(sale.total, const Money.rupees(2800));

        final loose = (await rows(
          'SELECT item_id, item_name_snapshot, unit_code_snapshot, '
          'line_total_paisa, cost_paisa FROM document_lines '
          'WHERE item_id IS NULL',
        )).single;
        expect(loose['item_name_snapshot'], 'Pyaz');
        expect(loose['unit_code_snapshot'], 'kg');
        expect(loose['line_total_paisa'], 30000);
        expect(loose['cost_paisa'], 0);

        // One stock row, for the oil. Nothing was taken off any shelf for the
        // onions, and nothing invented to say so.
        expect(await rows('SELECT item_id FROM stock_ledger'), [
          {'item_id': oil},
        ]);
        expect(await outOfBalance(), 0);
        expect(await accountNet('sales'), 280000);
        // Cost is the oil's alone: the onions' was never known.
        expect(await accountNet('cogs'), -210000);
        expect(
          (await rows(
            "SELECT cost_paisa FROM documents WHERE doc_type = 'sale_invoice'",
          )).single['cost_paisa'],
          210000,
        );

        // And the receipt carries it, by its name, at its amount.
        final receipt = await queries.receiptFor(firm.firmId, sale.documentId);
        final printed = receipt!.lines.firstWhere((l) => l.name == 'Pyaz');
        expect(printed.qtyDisplay, '2.5');
        expect(printed.unitCode, 'kg');
        expect(printed.amount, const Money.rupees(300));
      },
    );

    test('comes back as money only, and no more of it than was sold', () async {
      final sale = await sell(partyId: rashid);
      final sold = await queries.returnableLines(firm.firmId, sale.documentId);
      final onions = sold.firstWhere((l) => l.itemId == null);
      expect(onions.returnable, Qty.parse('2.500'));

      final back = await takeBack(
        actor,
        ReturnDraft(
          originalDocumentId: sale.documentId,
          lines: [
            ReturnLineDraft(
              documentLineId: onions.documentLineId,
              qty: Qty.parse('2.500'),
            ),
          ],
          reason: 'Gale hue thay',
        ),
      );
      expect(back.total, const Money.rupees(300));
      expect(
        await total(
          "SELECT COUNT(*) AS n FROM stock_ledger WHERE txn_type = 'sale_return'",
        ),
        0,
        reason: 'there is no shelf for loose onions to go back onto',
      );
      expect(await outOfBalance(), 0);
      expect(await accountNet('cogs'), -210000, reason: 'no cost came back');

      // Counted through the return, so it cannot come back twice.
      final after = await queries.returnableLines(firm.firmId, sale.documentId);
      expect(after.firstWhere((l) => l.itemId == null).returnable, Qty.zero);
      expect(after.firstWhere((l) => l.itemId == oil).returnable, Qty.one);
      await expectLater(
        takeBack(
          actor,
          ReturnDraft(
            originalDocumentId: sale.documentId,
            lines: [
              ReturnLineDraft(
                documentLineId: onions.documentLineId,
                qty: Qty.one,
              ),
            ],
            reason: 'Phir se',
          ),
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('a bill with one is cancelled cleanly', () async {
      final sale = await sell();
      await voidDocument(
        actor,
        documentId: sale.documentId,
        reason: 'Galat bill',
      );
      expect(await outOfBalance(), 0);
      expect(await accountNet('sales'), 0);
      expect(
        await total(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS n '
          'FROM stock_ledger',
        ),
        0,
        reason: 'the oil is back and nothing else ever left',
      );
    });
  });
}
