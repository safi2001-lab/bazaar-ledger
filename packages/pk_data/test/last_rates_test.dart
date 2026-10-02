import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// What a customer paid, and what a supplier charged, for one item before
/// (M37), read from a real database.
///
/// The counter asks this for every line of a named customer's bill, so the
/// answers have to be theirs and only theirs, newest first, and the read has
/// to cost their own history rather than the whole shop's.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordPurchaseUseCase buy;
  late VoidDocumentUseCase voidDocument;
  late String pcs;
  late String atta;
  late String rashid;
  late String bilal;
  late String faisalMills;
  late String sunriseFoods;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 1, 6));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    voidDocument = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));

    pcs =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    await runner.run(firm.actorAt(DateTime.utc(2026, 9, 1, 6)), (tx) async {
      atta = await tx.insert('items', {
        'name': 'Atta 10kg',
        'name_search': 'atta 10kg',
        'base_unit_id': pcs,
        'sale_rate_milli_paisa': Rate.rupees(1200).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(1000).inMilliPaisa,
      });
      Future<String> party(String name, String type) => tx.insert('parties', {
        'name': name,
        'name_search': name.toLowerCase(),
        'party_type': type,
      });
      rashid = await party('Rashid Traders', 'customer');
      bilal = await party('Bilal General Store', 'customer');
      faisalMills = await party('Faisal Flour Mills', 'supplier');
      sunriseFoods = await party('Sunrise Foods', 'supplier');
    });
  });

  tearDown(() async => db.close());

  /// A bill on udhaar for [partyId] on [day] of September, at [rupees] a
  /// bag, with [extra] more lines of the same bag at the same price.
  Future<PostedSale> sell(
    String partyId,
    int day,
    int rupees, {
    int qty = 1,
    int discountBp = 0,
    int extra = 0,
  }) => postSale(
    firm.actorAt(DateTime.utc(2026, 9, day, 6)),
    SaleDraft(
      partyId: partyId,
      lines: [
        for (var i = 0; i <= extra; i++)
          SaleLineDraft(
            itemId: atta,
            itemName: 'Atta 10kg',
            qty: Qty.units(qty),
            baseQty: Qty.units(qty),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
            discountBp: discountBp,
          ),
      ],
    ),
  );

  Future<void> deliver(String supplierId, int day, int rupees) => buy(
    firm.actorAt(DateTime.utc(2026, 9, day, 6)),
    PurchaseDraft(
      partyId: supplierId,
      lines: [
        PurchaseLineDraft(
          itemId: atta,
          itemName: 'Atta 10kg',
          qty: Qty.units(20),
          baseQty: Qty.units(20),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
    ),
  );

  group('last rates', () {
    test("a customer's are theirs alone, newest first, five at most", () async {
      await sell(rashid, 2, 1180);
      await sell(rashid, 4, 1170);
      await sell(bilal, 5, 1100); // somebody else's price
      await sell(rashid, 6, 1160, qty: 3, discountBp: 250);
      final cancelled = await sell(rashid, 7, 900);
      await sell(rashid, 8, 1150);
      await sell(rashid, 9, 1140);
      await sell(rashid, 10, 1130);
      await voidDocument(
        firm.actorAt(DateTime.utc(2026, 9, 10, 7)),
        documentId: cancelled.documentId,
        reason: 'Wrong customer',
      );

      final deals = await queries.lastSoldTo(
        firm.firmId,
        partyId: rashid,
        itemId: atta,
      );

      expect(
        [for (final d in deals) d.rate],
        [
          Rate.rupees(1130),
          Rate.rupees(1140),
          Rate.rupees(1150),
          // The cancelled Rs 900 was never a price anybody paid.
          Rate.rupees(1160),
          Rate.rupees(1170),
        ],
      );
      expect(deals.map((d) => d.dateLocal), [
        '2026-09-10',
        '2026-09-09',
        '2026-09-08',
        '2026-09-06',
        '2026-09-04',
      ]);
      final discounted = deals[3];
      expect(discounted.qty, Qty.units(3));
      expect(discounted.unitCode, 'pcs');
      expect(discounted.unitId, pcs);
      expect(discounted.discountBp, 250);
      expect(discounted.discount, const Money.rupees(87)); // 2.5% of 3,480
      expect(discounted.docNo, isNotEmpty);
    });

    test('lines of one bill at one price are one deal', () async {
      await sell(rashid, 3, 1180, extra: 2);
      final deals = await queries.lastSoldTo(
        firm.firmId,
        partyId: rashid,
        itemId: atta,
      );
      expect(deals, hasLength(1));
      expect(deals.single.qty, Qty.units(3));
    });

    test('what a supplier charged comes from deliveries, and from anybody '
        'when no supplier is named', () async {
      await deliver(faisalMills, 2, 980);
      await deliver(sunriseFoods, 3, 1010);
      await deliver(faisalMills, 5, 990);
      await sell(rashid, 6, 1200); // a sale is not a price the shop paid

      final fromFaisal = await queries.lastBought(
        firm.firmId,
        itemId: atta,
        supplierId: faisalMills,
      );
      expect(
        [for (final d in fromFaisal) d.rate],
        [Rate.rupees(990), Rate.rupees(980)],
      );
      final latest = await queries.lastBought(
        firm.firmId,
        itemId: atta,
        limit: 1,
      );
      expect(latest.single.rate, Rate.rupees(990));
      expect(latest.single.partyName, 'Faisal Flour Mills');
    });

    test("it is read through the party's own index, never a scan", () async {
      await sell(rashid, 2, 1180);
      Future<List<String>> plan(bool forParty) async {
        final rows = await db
            .customSelect(
              'EXPLAIN QUERY PLAN ${pastDealsSql(forParty: forParty)}',
              variables: [
                if (forParty) Variable<String>(rashid),
                Variable<String>(firm.firmId),
                Variable<String>('sale_invoice'),
                Variable<String>(atta),
                Variable<int>(5),
              ],
            )
            .get();
        return [for (final r in rows) r.read<String>('detail')];
      }

      final byParty = await plan(true);
      expect(byParty.join('\n'), contains('USING INDEX idx_documents_party'));
      expect(byParty.join('\n'), contains('USING INDEX idx_doclines_seq'));
      final byShop = await plan(false);
      expect(byShop.join('\n'), contains('USING INDEX idx_documents_list'));
      for (final step in [...byParty, ...byShop]) {
        expect(
          step,
          isNot(startsWith('SCAN')),
          reason: 'a full pass over a table, on every line of every bill',
        );
      }
    });
  });
}
