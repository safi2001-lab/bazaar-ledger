import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 9, 27, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// Books closed on the master, and a counter on the shop's wi-fi (M42),
/// over a real socket on this machine.
void main() {
  late _Ticking clock;
  late AppServices master;
  late AppServices counter;
  late String sugar;

  setUp(() async {
    clock = _Ticking();
    master = await openInMemoryServices(clock: clock);
    await master.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Master',
    );
    final firm = (await master.queries.currentFirm())!;
    final units = await master.queries.units(firm.id);
    sugar = await master.catalogue.addItem(
      master.actorNow(),
      ItemDraft(
        name: 'Sugar 1kg',
        baseUnitId: units.first.id,
        saleRate: Rate.rupees(160),
        openingStock: Qty.units(10),
        openingRate: Rate.rupees(140),
      ),
    );
    final port = await master.sync.startHosting(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    counter = await openInMemoryServices(clock: clock);
    await counter.sync.join(
      host: '127.0.0.1',
      port: port,
      code: master.sync.openJoining(),
      label: 'Counter 2',
    );
  });

  tearDown(() async {
    await counter.close();
    await master.close();
  });

  Future<PostedSale> sell(AppServices phone) async {
    final firm = (await phone.queries.currentFirm())!;
    final cash = (await phone.queries.paymentAccounts(
      firm.id,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final unit = (await phone.queries.units(firm.id)).first;
    return phone.postSale(
      phone.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: sugar,
            itemName: 'Sugar 1kg',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: unit.id,
            unitCode: unit.code,
            rate: Rate.rupees(160),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(160),
          ),
        ],
      ),
    );
  }

  group('closed books on the counters', () {
    test('a bill the counter made before it knew is taken in and shown to the '
        'owner, and the closing then binds the counter too', () async {
      // The counter rings a bill while the master, not yet synced, closes
      // the day it is dated.
      final early = await sell(counter);
      await master.audit.closeBooksThrough(BusinessDate('2026-09-27'));

      await counter.sync.syncNow();

      // Taken in: the money really moved, and refusing it would leave the
      // two phones disagreeing about the drawer.
      final firm = (await master.queries.currentFirm())!;
      final bills = await master.queries.recentSales(firm.id);
      expect(bills.map((b) => b.docNo), contains(early.docNo));
      final late = await master.audit.lateArrivals();
      expect(late.map((a) => a.number), [early.docNo]);
      expect(late.first.device, 'Counter 2');
      expect(late.first.dateLocal, '2026-09-27');
      expect((await master.checkHealth()).isHealthy, isTrue);

      // And the closing reached the counter with the rest of the books.
      expect((await counter.audit.locks()).closedThrough?.value, '2026-09-27');
      await expectLater(sell(counter), throwsA(isA<ApprovalNeeded>()));
    });
  });
}
