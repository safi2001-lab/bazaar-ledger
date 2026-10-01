import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A delivery challan, and the bill made from it, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late IssueChallanUseCase send;
  late PostSaleUseCase sell;
  late VoidDocumentUseCase cancel;
  late ActorContext actor;
  late String pcsUnitId;
  late String oilId;
  late String rashidId;
  late String bilalId;

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
    send = IssueChallanUseCase(writer: DriftChallanWriter(runner: runner));
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    cancel = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));
    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    await runner.run(actor, (tx) async {
      rashidId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      bilalId = await tx.insert('parties', {
        'name': 'Bilal Store',
        'name_search': 'bilal store',
        'party_type': 'customer',
      });
      oilId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(2000).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  SaleDraft cartons(int n, {String? from, String? to, Rate? rate}) => SaleDraft(
    partyId: to ?? rashidId,
    partyName: 'Rashid Traders',
    convertedFromId: from,
    lines: [
      SaleLineDraft(
        itemId: oilId,
        itemName: 'Cooking Oil 5L',
        qty: Qty.units(n),
        baseQty: Qty.units(n),
        unitId: pcsUnitId,
        unitCode: 'pcs',
        rate: rate ?? Rate.rupees(2400),
      ),
    ],
  );

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  Future<int> net(String systemKey) => count(
    'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
    'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
    "WHERE a.system_key = '$systemKey'",
  );

  Future<int> onShelf() =>
      count('SELECT COALESCE(SUM(qty_delta_thousandths), 0) FROM stock_ledger');

  test('a challan takes the goods off the shelf and owes nothing', () async {
    final c = await send(actor, cartons(40));

    expect(c.docNo, 'CHL-2627-0001');
    final row = await db
        .customSelect(
          'SELECT doc_type, total_paisa, balance_paisa, cost_paisa '
          'FROM documents',
        )
        .getSingle();
    expect(row.data['doc_type'], 'delivery_challan');
    expect(row.data['total_paisa'], 9600000);
    expect(row.data['balance_paisa'], 0);
    expect(row.data['cost_paisa'], 8000000);
    expect(await onShelf(), -40000);
    expect(await net('goods_on_challan'), 8000000);
    expect(await net('inventory'), -8000000);
    expect(await net('accounts_receivable'), 0);
    final party = await DriftAppQueries(db).partyById(firm.firmId, rashidId);
    expect(party!.balance, Money.zero);
  });

  test(
    'a bill from a challan moves no stock and costs what the goods left at',
    () async {
      final c = await send(actor, cartons(40));
      // A new consignment moves the average before the bill is made.
      await runner.run(actor, (tx) async {
        await tx.update('items', oilId, {
          'avg_cost_milli_paisa': Rate.rupees(2200).inMilliPaisa,
        });
      });

      final bill = await sell(
        actor,
        cartons(40, from: c.id, rate: Rate.rupees(2350)),
      );

      expect(await onShelf(), -40000);
      expect(await count('SELECT COUNT(*) FROM stock_ledger'), 1);
      expect(await net('goods_on_challan'), 0);
      expect(await net('cogs'), 8000000);
      expect(await net('accounts_receivable'), 9400000);
      final cost = await count(
        "SELECT cost_paisa FROM documents WHERE id = '${bill.documentId}'",
      );
      expect(cost, 8000000);
      final challans = await DriftAppQueries(db).challans(firm.firmId);
      expect(challans.single.billedAs, bill.docNo);
    },
  );

  test('a bill for other goods than the challan sent is refused', () async {
    final c = await send(actor, cartons(40));
    await expectLater(
      sell(actor, cartons(30, from: c.id)),
      throwsA(isA<ChallanRefused>()),
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      0,
    );
  });

  test('a challan is billed only to the customer it went to', () async {
    final c = await send(actor, cartons(40));
    await expectLater(
      sell(actor, cartons(40, from: c.id, to: bilalId)),
      throwsA(isA<ChallanRefused>()),
    );
  });

  test('a challan cannot be billed twice', () async {
    final c = await send(actor, cartons(40));
    await sell(actor, cartons(40, from: c.id));
    await expectLater(
      sell(actor, cartons(40, from: c.id)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('challan is already billed'),
        ),
      ),
    );
  });

  test('a cancelled challan puts the goods back on the shelf', () async {
    final c = await send(actor, cartons(40));
    await cancel(actor, documentId: c.id, reason: 'Came back on the van');

    expect(await onShelf(), 0);
    expect(await net('goods_on_challan'), 0);
    expect(await net('inventory'), 0);
    final challans = await DriftAppQueries(db).challans(firm.firmId);
    expect(challans.single.isVoid, isTrue);
  });

  test('a billed challan cannot be cancelled', () async {
    final c = await send(actor, cartons(40));
    await sell(actor, cartons(40, from: c.id));
    await expectLater(
      cancel(actor, documentId: c.id, reason: 'Came back'),
      throwsA(isA<VoidRefused>()),
    );
    expect(await onShelf(), -40000);
  });

  test('several challans to one customer are billed on one bill, at what '
      'the goods left at', () async {
    final monday = await send(actor, cartons(10));
    await runner.run(actor, (tx) async {
      await tx.update('items', oilId, {
        'avg_cost_milli_paisa': Rate.rupees(2100).inMilliPaisa,
      });
    });
    final thursday = await send(actor, cartons(5));

    final bill = await sell(
      actor,
      SaleDraft(
        partyId: rashidId,
        partyName: 'Rashid Traders',
        convertedFromId: monday.id,
        alsoFromIds: [thursday.id],
        lines: [
          SaleLineDraft(
            itemId: oilId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(15),
            baseQty: Qty.units(15),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(2400),
          ),
        ],
      ),
    );

    // 10 at Rs 2,000 and 5 at Rs 2,100: the cost each van-load left at.
    expect(await net('cogs'), 3050000);
    expect(await net('goods_on_challan'), 0);
    expect(await onShelf(), -15000);
    expect(await net('accounts_receivable'), 3600000);
    final links = await count(
      "SELECT COUNT(*) FROM doc_links WHERE to_document_id = '${bill.documentId}'",
    );
    expect(links, 2);
    final challans = await DriftAppQueries(db).challans(firm.firmId);
    expect(challans.every((c) => c.isBilled), isTrue);

    // Neither can be billed again.
    await expectLater(
      sell(actor, cartons(5, from: thursday.id)),
      throwsA(anything),
    );
  });

  test('challans to two customers are not one bill', () async {
    final a = await send(actor, cartons(10));
    final b = await send(actor, cartons(5, to: bilalId));
    await expectLater(
      sell(
        actor,
        SaleDraft(
          partyId: rashidId,
          partyName: 'Rashid Traders',
          convertedFromId: a.id,
          alsoFromIds: [b.id],
          lines: [
            SaleLineDraft(
              itemId: oilId,
              itemName: 'Cooking Oil 5L',
              qty: Qty.units(15),
              baseQty: Qty.units(15),
              unitId: pcsUnitId,
              unitCode: 'pcs',
              rate: Rate.rupees(2400),
            ),
          ],
        ),
      ),
      throwsA(isA<ChallanRefused>()),
    );
    expect(
      await count(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      0,
    );
  });

  test(
    'a quotation sent on a challan is tied to it, and goes only once',
    () async {
      final quote = await SaveQuotationUseCase(
        writer: DriftQuotationWriter(runner: runner),
      )(actor, cartons(10));
      final c = await send(actor, cartons(10, from: quote.id));
      final link = await count(
        "SELECT COUNT(*) FROM doc_links WHERE from_document_id = '${quote.id}' "
        "AND to_document_id = '${c.id}'",
      );
      expect(link, 1);
      await expectLater(
        send(actor, cartons(10, from: quote.id)),
        throwsA(isA<ChallanRefused>()),
      );
      await expectLater(
        sell(actor, cartons(10, from: quote.id)),
        throwsA(anything),
        reason: 'the quotation is already done; it is the challan to bill',
      );
      // A challan is billed, never sent on another challan.
      await expectLater(
        send(actor, cartons(10, from: c.id)),
        throwsA(isA<ChallanRefused>()),
      );
    },
  );

  test('a challan has to name its customer', () async {
    await expectLater(
      send(actor, cartons(40).withParty(null)),
      throwsA(isA<ChallanRefused>()),
    );
    expect(await count('SELECT COUNT(*) FROM documents'), 0);
  });
}

extension on SaleDraft {
  SaleDraft withParty(String? partyId) =>
      SaleDraft(lines: lines, partyId: partyId, partyName: partyName);
}
