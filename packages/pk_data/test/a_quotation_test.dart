import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A quotation, and the bill made from it, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late SaveQuotationUseCase quote;
  late PostSaleUseCase sell;
  late ActorContext actor;
  late String pcsUnitId;
  late String oilId;
  late String rashidId;

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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    quote = SaveQuotationUseCase(writer: DriftQuotationWriter(runner: runner));
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
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
      oilId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  SaleDraft forty({String? from}) => SaleDraft(
    partyId: rashidId,
    partyName: 'Rashid Traders',
    convertedFromId: from,
    lines: [
      SaleLineDraft(
        itemId: oilId,
        itemName: 'Cooking Oil 5L',
        qty: Qty.units(40),
        baseQty: Qty.units(40),
        unitId: pcsUnitId,
        unitCode: 'pcs',
        rate: Rate.rupees(2400),
      ),
    ],
  );

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  test(
    'a quotation is numbered and priced, and touches nothing else',
    () async {
      final q = await quote(actor, forty());

      expect(q.docNo, 'QUO-2627-0001');
      final row = await db
          .customSelect(
            'SELECT doc_type, status, total_paisa, balance_paisa, terms '
            'FROM documents',
          )
          .getSingle();
      expect(row.data['doc_type'], 'quotation');
      expect(row.data['status'], 'posted');
      expect(row.data['total_paisa'], 9600000);
      expect(row.data['balance_paisa'], 0);
      expect(row.data['terms'], 'Prices valid until 2026-10-11');
      expect(await count('SELECT COUNT(*) FROM document_lines'), 1);
      expect(await count('SELECT COUNT(*) FROM journal_entries'), 0);
      expect(await count('SELECT COUNT(*) FROM stock_ledger'), 0);
      expect(await count('SELECT COUNT(*) FROM payments'), 0);
    },
  );

  test('a quotation owes nothing on the khata', () async {
    await quote(actor, forty());
    final party = await DriftAppQueries(db).partyById(firm.firmId, rashidId);
    expect(party!.balance, Money.zero);
  });

  test('a bill made from a quotation is linked to it', () async {
    final q = await quote(actor, forty());
    final bill = await sell(actor, forty(from: q.id));

    final link = await db
        .customSelect(
          'SELECT from_document_id, to_document_id, link_type '
          'FROM doc_links',
        )
        .getSingle();
    expect(link.data['from_document_id'], q.id);
    expect(link.data['to_document_id'], bill.documentId);
    expect(link.data['link_type'], 'converted_from');
  });

  test('a quotation cannot be billed twice', () async {
    final q = await quote(actor, forty());
    await sell(actor, forty(from: q.id));
    await expectLater(sell(actor, forty(from: q.id)), throwsStateError);
    expect(
      await count(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      1,
    );
  });

  test('a quotation with nothing on it is refused', () async {
    await expectLater(
      quote(actor, SaleDraft(partyId: rashidId, lines: const [])),
      throwsA(isA<QuotationRefused>()),
    );
  });
}
