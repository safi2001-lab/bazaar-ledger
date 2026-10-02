import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Two shops in one database, and neither can see the other.
///
/// Every fixture in this suite used to hold exactly one firm, which meant
/// every `WHERE firm_id = ?` in the read layer could have been deleted without
/// a single test noticing. Multi-firm is M10, but the isolation has to be true
/// from the first row written — a leak discovered later is not a bug fix, it
/// is a data-breach notification.
void main() {
  late AppDatabase db;
  late DriftAppQueries queries;
  late _Shop first;
  late _Shop second;

  setUp(() async {
    db = await openTestDatabase();
    queries = DriftAppQueries(db);
    first = await _seed(db, 'Chishti Kiryana Store', 'Karachi');
    second = await _seed(db, 'Rehman Medical Store', 'Lahore');
  });

  tearDown(() => db.close());

  test('an item search never returns another shop\'s stock', () async {
    final mine = await queries.searchItems(first.firmId);
    final theirs = await queries.searchItems(second.firmId);

    expect(mine.map((i) => i.name), ['Cooking Oil 5L']);
    expect(theirs.map((i) => i.name), ['Panadol 500mg']);

    // And a search term that matches both shops' items still splits them.
    final both = await queries.searchItems(first.firmId, query: '0');
    expect(both.every((i) => i.name == 'Cooking Oil 5L'), isTrue);
  });

  test(
    'a barcode scanned in one shop does not find the other shop\'s item',
    () async {
      expect(
        (await queries.itemByBarcode(first.firmId, '8964000000001'))?.name,
        'Cooking Oil 5L',
      );
      expect(
        await queries.itemByBarcode(first.firmId, '8964000000002'),
        isNull,
        reason: 'that barcode belongs to the other shop',
      );
      expect(
        (await queries.itemByBarcode(second.firmId, '8964000000002'))?.name,
        'Panadol 500mg',
      );
    },
  );

  test('itemById refuses to reach across firms', () async {
    expect(await queries.itemById(first.firmId, first.itemId), isNotNull);
    expect(await queries.itemById(first.firmId, second.itemId), isNull);
  });

  test('a customer list is one shop\'s customers', () async {
    expect((await queries.searchParties(first.firmId)).map((p) => p.name), [
      'Bilal General Store',
    ]);
    expect((await queries.searchParties(second.firmId)).map((p) => p.name), [
      'Sadiq Traders',
    ]);
  });

  test('a khata balance counts only this shop\'s bills', () async {
    // The same customer name in both shops, each owing a different amount.
    // A balance subquery missing its firm predicate silently adds them up.
    final mine = (await queries.searchParties(first.firmId)).single;
    final theirs = (await queries.searchParties(second.firmId)).single;

    expect(mine.balance, Money.rupees(1000));
    expect(theirs.balance, Money.rupees(7000));
  });

  test('the day book is one shop\'s day', () async {
    final today = BusinessDate.now(const SystemClock()).value;
    final mine = await queries.dayTotals(first.firmId, today);
    final theirs = await queries.dayTotals(second.firmId, today);

    expect(mine.billCount, 1);
    expect(theirs.billCount, 1);
    expect(mine.sales, Money.rupees(1000));
    expect(theirs.sales, Money.rupees(7000));
  });

  test('a sales list is one shop\'s sales', () async {
    final mine = await queries.recentSales(first.firmId);
    final theirs = await queries.recentSales(second.firmId);

    expect(mine, hasLength(1));
    expect(theirs, hasLength(1));
    expect(mine.single.total, Money.rupees(1000));
    expect(theirs.single.total, Money.rupees(7000));
  });

  test(
    'a receipt carries its own shop, not the first one in the table',
    () async {
      // The header used to be read as "the first firm by creation date", which
      // prints the wrong name, NTN and bank details on every receipt the second
      // shop ever issues.
      final mine = await queries.receiptFor(first.firmId, first.documentId);
      final theirs = await queries.receiptFor(second.firmId, second.documentId);

      expect(mine!.shop.name, 'Chishti Kiryana Store');
      expect(theirs!.shop.name, 'Rehman Medical Store');
      expect(mine.shop.city, 'Karachi');
      expect(theirs.shop.city, 'Lahore');
    },
  );

  test('a receipt cannot be fetched with the wrong firm', () async {
    expect(await queries.receiptFor(first.firmId, second.documentId), isNull);
  });

  test('payment accounts and units are per shop', () async {
    // Seven each: one per tender the counter offers.
    final mineAccounts = await queries.paymentAccounts(first.firmId);
    final theirAccounts = await queries.paymentAccounts(second.firmId);
    expect(mineAccounts, hasLength(7));
    expect(theirAccounts, hasLength(7));
    expect(
      mineAccounts.map((a) => a.modeLabel).toSet(),
      theirAccounts.map((a) => a.modeLabel).toSet(),
      reason: 'both shops offer the same tenders',
    );
    expect(
      mineAccounts
          .map((a) => a.id)
          .toSet()
          .intersection(theirAccounts.map((a) => a.id).toSet()),
      isEmpty,
      reason: 'and not one row of it is shared between them',
    );
    // Eighteen: pcs, dozen, kg, g, maund, seer, tola, l, ml, cm, m, gaz,
    // since M56 carton, dabba, packet, strip and tablet, and since M53 the
    // bori.
    expect(await queries.units(first.firmId), hasLength(18));
    expect(await queries.units(second.firmId), hasLength(18));
  });
}

final class _Shop {
  _Shop({
    required this.firmId,
    required this.itemId,
    required this.partyId,
    required this.documentId,
  });

  final String firmId;
  final String itemId;
  final String partyId;
  final String documentId;
}

/// A whole shop: first run, one item, one customer, one bill on udhaar.
Future<_Shop> _seed(AppDatabase db, String name, String city) async {
  final ids = UlidGenerator();
  final clock = const SystemClock();

  final run = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
    shopName: name,
    ownerName: 'Malik Sahib',
    deviceLabel: 'Counter 1',
    platform: 'test',
    city: city,
    allowSecondFirm: true,
  );

  final hlc = await resumeHlcClock(db, deviceId: run.deviceId, clock: clock);
  final runner = TxRunner(database: db, ids: ids, hlc: hlc);
  final actor = ActorContext(
    firmId: run.firmId,
    userId: run.ownerUserId,
    deviceId: run.deviceId,
    startedAtUtc: clock.nowUtc(),
  );

  final isFirst = city == 'Karachi';
  final catalogue = DriftCatalogueWriter(runner);
  final units = await DriftAppQueries(db).units(run.firmId);
  final pcs = units.firstWhere((u) => u.code == 'pcs');

  final itemId = await catalogue.addItem(
    actor,
    ItemDraft(
      name: isFirst ? 'Cooking Oil 5L' : 'Panadol 500mg',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(isFirst ? 1000 : 7000),
      barcode: isFirst ? '8964000000001' : '8964000000002',
      openingStock: Qty.units(50),
      openingRate: Rate.rupees(isFirst ? 600 : 4000),
    ),
  );

  final partyId = await catalogue.addParty(
    actor,
    PartyDraft(name: isFirst ? 'Bilal General Store' : 'Sadiq Traders'),
  );

  final posted = await PostSaleUseCase(writer: DriftSaleWriter(runner: runner))
      .call(
        actor,
        SaleDraft(
          partyId: partyId,
          lines: [
            SaleLineDraft(
              itemId: itemId,
              itemName: isFirst ? 'Cooking Oil 5L' : 'Panadol 500mg',
              qty: Qty.one,
              baseQty: Qty.one,
              unitCode: 'pcs',
              rate: Rate.rupees(isFirst ? 1000 : 7000),
            ),
          ],
          roundToRupee: false,
        ),
      );

  return _Shop(
    firmId: run.firmId,
    itemId: itemId,
    partyId: partyId,
    documentId: posted.documentId,
  );
}
