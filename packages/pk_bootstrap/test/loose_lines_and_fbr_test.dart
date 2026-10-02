import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A loose line on a shop that reports to FBR (M37).
///
/// FBR's Digital Invoicing wants an HS code on every line, and a line with
/// no item has none. The counter does not offer one there; this is the
/// service boundary saying it again, for whatever gets past the counter.
void main() {
  late AppServices shop;
  late String firmId;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 10, 2, 6)),
    );
    await shop.setUpShop(
      shopName: 'Rashid Traders',
      ownerName: 'Rashid',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
  });

  tearDown(() => shop.close());

  Future<PostedSale> sellOnions() async {
    final cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    return shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: null,
            itemName: 'Pyaz',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitCode: 'kg',
            rate: Rate.rupees(150),
            tracksStock: false,
          ),
        ],
        // A Rs 1,000 note: a registered shop charges sales tax on the line
        // as on anything without a rule of its own, so the bill is more
        // than the Rs 300 of onions.
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(1000),
          ),
        ],
      ),
    );
  }

  group('loose lines and fbr', () {
    test('a shop that does not report sells one', () async {
      expect(await shop.fbr.reportsSales(), isFalse);
      final sale = await sellOnions();
      expect(sale.total, const Money.rupees(300));
    });

    test(
      'a shop reporting to FBR refuses one in words, and nothing is written',
      () async {
        await shop.updateFirm({
          'is_sales_tax_registered': 1,
          'ntn': '1234567-8',
          'strn': '3277876123456',
        });
        await shop.fbr.save(
          const FbrSettings(enabled: true, token: 'pral-token'),
        );
        expect(await shop.fbr.reportsSales(), isTrue);

        await expectLater(
          sellOnions(),
          throwsA(
            isA<FbrRefusedLine>().having(
              (e) => e.reason,
              'reason',
              contains('HS code'),
            ),
          ),
        );
        final bills = await shop.database
            .customSelect(
              'SELECT COUNT(*) AS n FROM documents '
              "WHERE doc_type = 'sale_invoice'",
            )
            .getSingle();
        expect(bills.read<int>('n'), 0, reason: 'the bill was written');
      },
    );
  });
}
