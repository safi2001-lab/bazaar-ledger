import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The paper the customer keeps has to add up.
///
/// `pk_platform`'s own suite already proves the LAYOUT reconciles — given a
/// tender, a change and a total that agree, it prints them so that they still
/// agree. What it cannot prove is that the numbers handed to it are the right
/// ones, because it is handed a fixture.
///
/// They were not. Two separate faults in the mapping from the database to
/// `ReceiptData`, both invisible to every test in the repository, both on
/// every receipt the shop prints:
///
///   * The cash line printed what the bill TOOK, not what the customer HANDED
///     OVER. A Rs 5,525 bill paid with a Rs 6,000 note printed "Cash 5,525"
///     and "Change 475" — which comes to 5,050 — and told the customer they
///     had handed over 5,525.
///   * A discounted line printed its NET amount, with the discount printed
///     again underneath it as a deduction, under a gross Subtotal. Three
///     numbers, none of which agreed with the other two.
///
/// So this test starts from a real posted sale and checks the arithmetic a
/// customer does with their thumb.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase postSale;
  late DriftAppQueries queries;
  late String pcsUnitId;
  late String oilId;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
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
    catalogue = DriftCatalogueWriter(runner);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    queries = DriftAppQueries(db);

    pcsUnitId = (await db
            .customSelect("SELECT id FROM units WHERE code = 'pcs'")
            .getSingle())
        .read<String>('id');

    oilId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcsUnitId,
        saleRate: const Rate.rupees(100),
        openingStock: Qty.units(50),
        openingRate: const Rate.rupees(60),
      ),
    );
  });

  tearDown(() async => db.close());

  Money parse(String s) => Money.parse(s.replaceAll(',', ''));

  /// The amount on a printed line, found by its label.
  Money amountOn(List<String> lines, String label) {
    // The label followed by whitespace, so "Cash" does not also match the
    // "Cashier   Malik Sahib" line at the top of every receipt.
    final pattern = RegExp('^\\s*${RegExp.escape(label)}\\s');
    final line = lines.firstWhere(
      pattern.hasMatch,
      orElse: () =>
          throw StateError('no "$label" line in:\n${lines.join('\n')}'),
    );
    return parse(line.substring(line.lastIndexOf(' ') + 1).replaceAll('-', ''));
  }

  Future<List<String>> printedReceiptFor(String documentId) async {
    final data = await queries.receiptFor(firm.firmId, documentId);
    expect(data, isNotNull);
    return const ThermalReceiptRenderer().toPreview(data!);
  }

  test('cash in, minus change out, is the bill', () async {
    // Rs 200 of oil, paid with a Rs 500 note.
    final posted = await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: oilId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: const Rate.rupees(100),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: firm.cashPaymentAccountId,
            mode: 'cash',
            amount: const Money.rupees(500),
            tendered: const Money.rupees(500),
          ),
        ],
      ),
    );

    final lines = await printedReceiptFor(posted.documentId);
    final text = lines.join('\n');

    expect(
      text,
      contains('500.00'),
      reason: 'the note the customer handed over is not on the receipt',
    );

    final cash = amountOn(lines, 'Cash');
    final change = amountOn(lines, 'Change');
    final total = amountOn(lines, 'TOTAL');

    expect(total, const Money.rupees(200));
    expect(
      cash - change,
      total,
      reason: 'cash in minus change out must be the bill; the paper said '
          '$cash - $change, which is ${cash - change}',
    );
  });

  test('a discounted line prints three numbers that agree', () async {
    // One tin at Rs 100, 10% off. Gross 100, discount 10, net 90.
    final posted = await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: oilId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.one,
            baseQty: Qty.one,
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: const Rate.rupees(100),
            discountBp: 1000,
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: firm.cashPaymentAccountId,
            mode: 'cash',
            amount: const Money.rupees(90),
            tendered: const Money.rupees(90),
          ),
        ],
      ),
    );

    final lines = await printedReceiptFor(posted.documentId);

    final subtotal = amountOn(lines, 'Subtotal');
    final discount = amountOn(lines, 'Discount');
    final total = amountOn(lines, 'TOTAL');

    expect(subtotal, const Money.rupees(100), reason: 'subtotal is gross');
    expect(discount, const Money.rupees(10));
    expect(
      subtotal - discount,
      total,
      reason: 'the printed components must reconcile to the printed total',
    );

    // And the line itself: the rate times the quantity, with the discount
    // shown once, beneath it.
    final detail = lines.firstWhere((l) => l.contains(' x '));
    final printedAmount = parse(detail.substring(detail.lastIndexOf(' ') + 1));
    expect(
      printedAmount,
      const Money.rupees(100),
      reason: 'the Amount column must print the gross, because the discount '
          'is printed again on the line below it and the Subtotal is gross '
          'too. Printing the net deducted the discount twice on the paper: '
          'the column summed to 90 while the Subtotal claimed 100, and '
          'reading the line as printed gave 80. Line was: "$detail"',
    );
    expect(
      lines.any((l) => l.contains('less discount')),
      isTrue,
    );
  });

  test('a bill paid to the paisa prints no change and still reconciles',
      () async {
    final posted = await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: oilId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.one,
            baseQty: Qty.one,
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: const Rate.rupees(100),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: firm.cashPaymentAccountId,
            mode: 'cash',
            amount: const Money.rupees(100),
            tendered: const Money.rupees(100),
          ),
        ],
      ),
    );

    final lines = await printedReceiptFor(posted.documentId);
    expect(amountOn(lines, 'Cash'), const Money.rupees(100));
    expect(amountOn(lines, 'TOTAL'), const Money.rupees(100));
    expect(
      lines.any((l) => l.trimLeft().startsWith('Change')),
      isFalse,
      reason: 'no change was given, so no change line',
    );
  });
}
