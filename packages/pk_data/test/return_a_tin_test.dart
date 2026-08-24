import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A customer bringing goods back, against a real database.
///
/// The builder tests prove the arithmetic. These prove the rows land, the
/// stock comes back at the snapshot cost even after the average has moved,
/// and the limit holds ACROSS visits — which is the half that needs a
/// database to be true at all.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordPurchaseUseCase buy;
  late RecordReturnUseCase takeBack;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String partyId;
  late String cashAccountId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    db = await openTestDatabase();
    ids = UlidGenerator(now: clock.nowUtc);
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
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    takeBack = RecordReturnUseCase(writer: DriftReturnWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      partyId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      riceId = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(90).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  Future<PostedSale> sell({int qty = 5, bool onUdhaar = true}) => postSale(
    actor,
    SaleDraft(
      partyId: onUdhaar ? partyId : null,
      lines: [
        SaleLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: onUdhaar
          ? const []
          : [
              TenderDraft(
                paymentAccountId: cashAccountId,
                mode: 'cash',
                amount: Money.rupees(150 * qty),
              ),
            ],
    ),
  );

  Future<String> lineOf(String documentId) async =>
      (await db
              .customSelect(
                'SELECT id FROM document_lines WHERE document_id = ?',
                variables: [Variable<String>(documentId)],
              )
              .getSingle())
          .read<String>('id');

  Future<RecordedReturn> takeOne(
    PostedSale sale, {
    int qty = 1,
    Money refund = Money.zero,
  }) async => takeBack(
    actor,
    ReturnDraft(
      originalDocumentId: sale.documentId,
      reason: 'Packet phata hua tha',
      refundNow: refund,
      paymentAccountId: refund.isPositive ? cashAccountId : null,
      lines: [
        ReturnLineDraft(
          documentLineId: await lineOf(sale.documentId),
          qty: Qty.units(qty),
        ),
      ],
    ),
  );

  test('one tin off a bill for five comes back', () async {
    final sale = await sell();

    final returned = await takeOne(sale);

    expect(returned.total, const Money.rupees(150));
    expect(returned.docNo, startsWith('SRN-'));

    final balance = await db
        .customSelect(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS b '
          'FROM stock_ledger WHERE item_id = ?',
          variables: [Variable<String>(riceId)],
        )
        .getSingle();
    expect(balance.read<int>('b'), -4000);
  });

  test('the books balance afterwards', () async {
    final sale = await sell();
    await takeOne(sale);

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('d'), totals.read<int>('c'));
  });

  test('the credit comes off the khata', () async {
    final sale = await sell();
    expect(
      (await queries.partyById(firm.firmId, partyId))!.balance,
      const Money.rupees(750),
    );

    final returned = await takeOne(sale);

    expect(returned.againstBill, const Money.rupees(150));
    expect(returned.onAccount, Money.zero);
    expect(
      (await queries.partyById(firm.firmId, partyId))!.balance,
      const Money.rupees(600),
      reason:
          'the ledger says the udhaar came down and the khata does not, so '
          'the two numbers a shopkeeper reads disagree',
    );
  });

  test('a cash sale returned for cash owes nobody anything', () async {
    final sale = await sell(onUdhaar: false);

    final returned = await takeOne(sale, refund: const Money.rupees(150));

    expect(returned.refunded, const Money.rupees(150));
    expect(returned.againstBill, Money.zero);
    expect(returned.onAccount, Money.zero);
  });

  test(
    'a return against a settled bill becomes credit, not a refund',
    () async {
      // The case the credit split exists for. The customer paid the bill in
      // full and then brought a tin back without taking cash: the shop is now
      // holding Rs 150 for them, and crediting Receivables would say their
      // udhaar came down from a balance that is already zero.
      final sale = await sell();
      final firmId = firm.firmId;
      await RecordReceiptUseCase(
        writer: DriftPaymentWriter(runner: runner),
      ).call(
        actor,
        ReceiptDraft(
          partyId: partyId,
          amount: const Money.rupees(750),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );
      expect((await queries.partyById(firmId, partyId))!.balance, Money.zero);

      final returned = await takeOne(sale);

      expect(returned.againstBill, Money.zero);
      expect(returned.onAccount, const Money.rupees(150));
      expect(
        (await queries.partyById(firmId, partyId))!.balance,
        const Money.rupees(-150),
        reason: 'the shop is holding the customer money and does not show it',
      );
    },
  );

  test('the stock comes back at what it left at, not at today', () async {
    // Sell at a cost of Rs 90, then take a delivery at Rs 200 so the average
    // moves, then return. Bringing the tin back at Rs 200 would book a
    // profit on a customer changing their mind.
    final sale = await sell();

    await buy(
      actor,
      PurchaseDraft(
        partyId: partyId,
        lines: [
          PurchaseLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(200),
          ),
        ],
      ),
    );

    final returned = await takeOne(sale);

    final movement = await db
        .customSelect(
          'SELECT value_delta_paisa FROM stock_ledger '
          "WHERE txn_type = 'sale_return'",
        )
        .getSingle();
    expect(
      movement.read<int>('value_delta_paisa'),
      const Money.rupees(90).inPaisa,
      reason:
          'the tin came back at the price of a later delivery, so the shop '
          'booked a profit on a customer changing their mind',
    );

    final doc = await db
        .customSelect(
          'SELECT cost_paisa FROM documents WHERE id = ?',
          variables: [Variable<String>(returned.documentId)],
        )
        .getSingle();
    expect(doc.read<int>('cost_paisa'), const Money.rupees(90).inPaisa);
  });

  test('the return is linked to the bill it came off', () async {
    final sale = await sell();
    final returned = await takeOne(sale);

    final link = await db
        .customSelect(
          'SELECT from_document_id, to_document_id, link_type '
          'FROM doc_links',
        )
        .getSingle();

    expect(link.read<String>('from_document_id'), sale.documentId);
    expect(link.read<String>('to_document_id'), returned.documentId);
    expect(link.read<String>('link_type'), 'returns');
  });

  group('the limit holds across visits', () {
    test('a second return can only take what the first left', () async {
      // Without counting through doc_links, a customer can return the same
      // tin every day and walk a shop out of its stock one bill at a time.
      final sale = await sell(qty: 2);
      await takeOne(sale);

      await expectLater(takeOne(sale, qty: 2), throwsA(isA<ReturnRefused>()));

      // And exactly what is left still works.
      final second = await takeOne(sale);
      expect(second.total, const Money.rupees(150));
    });

    test('and a third finds nothing left', () async {
      final sale = await sell(qty: 2);
      await takeOne(sale);
      await takeOne(sale);

      await expectLater(takeOne(sale), throwsA(isA<ReturnRefused>()));
    });
  });

  group('what it refuses', () {
    test('a bill that does not exist', () async {
      await expectLater(
        takeBack(
          actor,
          const ReturnDraft(
            originalDocumentId: 'nothing',
            reason: 'Typo',
            lines: [ReturnLineDraft(documentLineId: 'x', qty: Qty.raw(1000))],
          ),
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('a failure leaves nothing behind', () async {
      final sale = await sell(qty: 2);
      final before = await db
          .customSelect('SELECT COUNT(*) AS n FROM documents')
          .getSingle();

      await expectLater(takeOne(sale, qty: 5), throwsA(isA<ReturnRefused>()));

      final after = await db
          .customSelect('SELECT COUNT(*) AS n FROM documents')
          .getSingle();
      expect(after.read<int>('n'), before.read<int>('n'));

      // And no link either. The first version of this asserted the row count
      // was `isNotNull`, which a count always is — a test that could not
      // fail, dressed as one that could.
      final links = await db
          .customSelect('SELECT COUNT(*) AS n FROM doc_links')
          .getSingle();
      expect(links.read<int>('n'), 0);
    });
  });

  test('the return is recorded in the audit trail', () async {
    final sale = await sell();
    final returned = await takeOne(sale);

    final audit = await db
        .customSelect(
          'SELECT entity_id, summary FROM audit_log '
          "WHERE action_code = 'SALE_RETURNED'",
        )
        .getSingle();

    expect(audit.read<String>('entity_id'), returned.documentId);
    expect(audit.read<String>('summary'), contains(sale.docNo));
    expect(audit.read<String>('summary'), contains('Packet phata hua tha'));
  });
}
