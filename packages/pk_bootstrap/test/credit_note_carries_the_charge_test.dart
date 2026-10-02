import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// FBR as a stand-in: posts everything, and keeps what it was sent.
final class _FakeFbr implements FbrGateway {
  final sent = <String>[];
  var _next = 1;

  @override
  Future<FbrOutcome> post(String payloadJson) async {
    sent.add(payloadJson);
    return FbrPosted('7000007DI000000000${_next++}');
  }
}

/// A credit note to FBR (M28) for goods returned off a discounted line sold
/// in maunds carries what the return gave back (M57): the quantity in the
/// unit sold, the line's own discount, the tax at the rate it was charged,
/// and the total the customer got back — read off the return's own lines,
/// which now hold exactly that, never the list price.
void main() {
  late AppServices shop;
  late _FakeFbr fbr;
  late String firmId;
  late String atta;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 10, 3, 6)),
    );
    await shop.setUpShop(
      shopName: 'Rashid Traders',
      ownerName: 'Rashid',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    await shop.updateFirm({
      'is_sales_tax_registered': 1,
      'ntn': '1234567-8',
      'strn': '3277876123456',
    });
    final kg = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'kg');
    atta = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Atta Chakki',
        baseUnitId: kg.id,
        saleRate: Rate.rupees(125),
        hsCode: '1101.0010',
        openingStock: Qty.units(200),
        openingRate: Rate.rupees(110),
      ),
    );
    fbr = _FakeFbr();
    shop.fbr.gatewayFor = (_) => fbr;
    await shop.fbr.save(const FbrSettings(enabled: true, token: 'pral-token'));
  });

  tearDown(() => shop.close());

  test(
    'fbr credit note a return off a discounted maund carries what came back',
    () async {
      final units = await shop.queries.units(firmId);
      final maund = units.firstWhere((u) => u.code == 'maund');
      final cash = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cash');

      // Two maunds at Rs 5,000 less 10%: Rs 9,000 of atta and Rs 1,620 of
      // sales tax, Rs 10,620 at the counter.
      final sale = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          roundToRupee: false,
          lines: [
            SaleLineDraft(
              itemId: atta,
              itemName: 'Atta Chakki',
              hsCode: '1101.0010',
              qty: Qty.units(2),
              baseQty: Qty.units(80),
              unitId: maund.id,
              unitCode: 'maund',
              rate: Rate.rupees(5000),
              discountBp: 1000,
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash.id,
              mode: 'cash',
              amount: const Money.rupees(10620),
            ),
          ],
        ),
      );
      expect(sale.total, const Money.rupees(10620));
      await shop.fbr.afterSale(sale.documentId);
      await shop.fbr.sendPending();

      final line = (await shop.queries.returnableLines(
        firmId,
        sale.documentId,
      )).single;
      expect(line.returnable, Qty.units(2));

      // Half a maund back, for a quarter of what the line was charged.
      final back = await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Keera laga hua',
          refundNow: const Money.rupees(2655),
          paymentAccountId: cash.id,
          lines: [
            ReturnLineDraft(
              documentLineId: line.documentLineId,
              qty: Qty.parse('0.5'),
            ),
          ],
        ),
      );
      expect(back.total, const Money.rupees(2655));
      await shop.fbr.afterReturn(back.documentId);
      await shop.fbr.sendPending();

      final note = fbr.sent.last;
      expect(note, contains('"InvoiceType":"Credit Note"'));
      expect(note, contains('"HSCode":"1101.0010"'));
      expect(note, contains('"Quantity":0.500'));
      expect(note, contains('"UnitOfMeasurement":"maund"'));
      expect(note, contains('"UnitPrice":5000.00'));
      expect(note, contains('"SalesTaxRate":18.00'));
      expect(note, contains('"SalesTaxAmount":405.00'));
      expect(note, contains('"Discount":250.00'));
      expect(note, contains('"TotalAmount":2655.00'));
      expect(note, contains('"TotalTaxableAmount":2250.00'));
      expect(note, contains('"TotalInvoiceAmount":2655.00'));
    },
  );
}
