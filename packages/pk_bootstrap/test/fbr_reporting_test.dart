import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// FBR as a stand-in: answers whatever the test tells it to, and keeps what
/// it was sent.
final class _FakeFbr implements FbrGateway {
  final sent = <String>[];
  FbrOutcome Function() answer = () => const FbrPosted('7000007DI0000000001');

  @override
  Future<FbrOutcome> post(String payloadJson) async {
    sent.add(payloadJson);
    return answer();
  }
}

void main() {
  late AppServices shop;
  late _FakeFbr fbr;
  late String firmId;
  late String oil;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 9, 30, 6)),
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
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(2500),
        hsCode: '1512.1900',
        openingStock: Qty.units(50),
      ),
    );
    fbr = _FakeFbr();
    shop.fbr.gatewayFor = (_) => fbr;
  });

  tearDown(() => shop.close());

  Future<String> sell() async {
    final cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    final posted = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            hsCode: '1512.1900',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(2950),
          ),
        ],
      ),
    );
    await shop.fbr.afterSale(posted.documentId);
    return posted.documentId;
  }

  Future<Map<String, Object?>> fbrOf(String id) async =>
      (await shop.database
              .customSelect(
                'SELECT fbr_status, fbr_invoice_no, fbr_error FROM documents '
                'WHERE id = ?',
                variables: [Variable<String>(id)],
              )
              .getSingle())
          .data;

  Future<void> turnOn() =>
      shop.fbr.save(const FbrSettings(enabled: true, token: 'pral-token'));

  group('fbr reporting', () {
    test(
      'a bill made while reporting is sent and comes back numbered',
      () async {
        await turnOn();
        final bill = await sell();
        expect((await fbrOf(bill))['fbr_status'], 'pending');
        final receipt = await shop.queries.receiptFor(firmId, bill);
        expect(receipt!.fbrPending, isTrue);

        final report = await shop.fbr.sendPending();
        expect(report.posted, 1);
        final row = await fbrOf(bill);
        expect(row['fbr_status'], 'posted');
        expect(row['fbr_invoice_no'], '7000007DI0000000001');
        expect(fbr.sent.single, contains('"HSCode":"1512.1900"'));
        expect(fbr.sent.single, contains('"SellerNTN":"1234567-8"'));
        expect(
          (await shop.queries.receiptFor(firmId, bill))!.fbrInvoiceNo,
          '7000007DI0000000001',
        );
      },
    );

    test(
      'FBR out of reach leaves the bill waiting, to be sent later',
      () async {
        await turnOn();
        final bill = await sell();
        fbr.answer = () => const FbrTryLater('No connection to FBR.');
        final report = await shop.fbr.sendPending();
        expect(report.waiting, 1);
        expect((await fbrOf(bill))['fbr_status'], 'pending');

        fbr.answer = () => const FbrPosted('7000007DI0000000002');
        await shop.fbr.sendPending();
        expect((await fbrOf(bill))['fbr_status'], 'posted');
      },
    );

    test('a bill FBR would refuse is held back and says why', () async {
      await turnOn();
      await shop.updateFirm({'ntn': null});
      final bill = await sell();
      await shop.fbr.sendPending();
      final row = await fbrOf(bill);
      expect(row['fbr_status'], 'rejected');
      expect('${row['fbr_error']}', contains('1001'));
      expect(fbr.sent, isEmpty, reason: 'nothing FBR would refuse is sent');

      await shop.updateFirm({'ntn': '1234567-8'});
      await shop.fbr.retry(bill);
      await shop.fbr.sendPending();
      expect((await fbrOf(bill))['fbr_status'], 'posted');
    });

    test(
      'a shop that does not report sends nothing, and an unregistered one cannot',
      () async {
        final bill = await sell();
        expect((await fbrOf(bill))['fbr_status'], isNull);
        await shop.fbr.sendPending();
        expect(fbr.sent, isEmpty);

        await shop.updateFirm({'is_sales_tax_registered': 0});
        await expectLater(turnOn(), throwsA(isA<PermissionDenied>()));
      },
    );
  });
}
