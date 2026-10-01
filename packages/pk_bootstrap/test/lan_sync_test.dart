import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look, so which of
/// two edits came later is never a tie.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 9, 27, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// Two phones on one shop's wi-fi, over a real socket on this machine.
void main() {
  late _Ticking clock;
  late AppServices master;
  late AppServices counter;
  late int port;
  late String sugar;

  Future<AppServices> joined(String label) async {
    final phone = await openInMemoryServices(clock: clock);
    await phone.sync.join(
      host: '127.0.0.1',
      port: port,
      code: master.sync.openJoining(),
      label: label,
    );
    return phone;
  }

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
    port = await master.sync.startHosting(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    counter = await joined('Counter 2');
  });

  tearDown(() async {
    await counter.close();
    await master.close();
  });

  Future<String> sell(AppServices phone, int pieces) async {
    final firm = (await phone.queries.currentFirm())!;
    final cash = (await phone.queries.paymentAccounts(
      firm.id,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final unit = (await phone.queries.units(firm.id)).first;
    final posted = await phone.postSale(
      phone.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: sugar,
            itemName: 'Sugar 1kg',
            qty: Qty.units(pieces),
            baseQty: Qty.units(pieces),
            unitId: unit.id,
            unitCode: unit.code,
            rate: Rate.rupees(160),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(160 * pieces),
          ),
        ],
      ),
    );
    return posted.docNo;
  }

  Future<Qty> stockOn(AppServices phone) async {
    final firm = (await phone.queries.currentFirm())!;
    return (await phone.queries.searchItems(
      firm.id,
      query: 'Sugar',
    )).single.stockOnHand;
  }

  Future<int> count(AppServices phone, String sql) async =>
      (await phone.database.customSelect(sql).getSingle()).read<int>('n');

  group('lan sync', () {
    test('a counter joins the master and opens the whole shop', () async {
      expect(
        (await counter.queries.currentFirm())!.name,
        'Chishti Kiryana Store',
      );
      expect(await counter.sync.isCounter(), isTrue);
      expect(await master.sync.isCounter(), isFalse);
      expect(await stockOn(counter), Qty.units(10));
      final devices = await counter.sync.devices();
      expect(devices.map((d) => (d.label, d.role, d.prefix)), [
        ('Master', 'master', ''),
        ('Counter 2', 'counter', 'B'),
      ]);
      expect(devices.where((d) => d.isThisDevice).single.label, 'Counter 2');
      expect((await counter.checkHealth()).isHealthy, isTrue);
    });

    test("a sale on the counter reaches the master's books", () async {
      final bill = await sell(counter, 2);
      expect(bill, contains('-B'), reason: "the counter's own letter");

      final report = await counter.sync.syncNow();
      expect(report.sent.applied, greaterThan(0));

      final firm = (await master.queries.currentFirm())!;
      final bills = await master.database
          .customSelect(
            "SELECT doc_no FROM documents WHERE doc_type = 'sale_invoice' "
            'AND firm_id = ?',
            variables: [Variable<String>(firm.id)],
          )
          .get();
      expect(bills.map((r) => r.read<String>('doc_no')), [bill]);
      expect(await stockOn(master), Qty.units(8));
      final health = await master.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });

    test('two tills selling at once both count against the stock', () async {
      final atMaster = await sell(master, 3);
      final atCounter = await sell(counter, 2);
      expect(atMaster, isNot(atCounter));

      await counter.sync.syncNow();

      expect(await stockOn(master), Qty.units(5));
      expect(await stockOn(counter), Qty.units(5));
      for (final phone in [master, counter]) {
        final health = await phone.checkHealth();
        expect(health.isHealthy, isTrue, reason: health.toString());
        expect(
          await count(
            phone,
            "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice'",
          ),
          2,
        );
      }
    });

    test('the later of two edits wins on both phones', () async {
      final firm = (await master.queries.currentFirm())!;
      final unit = (await master.queries.units(firm.id)).first;
      ItemDraft named(String name) => ItemDraft(
        name: name,
        baseUnitId: unit.id,
        saleRate: Rate.rupees(160),
      );

      await master.catalogue.updateItem(
        master.actorNow(),
        sugar,
        named('Cheeni 1kg'),
      );
      await counter.catalogue.updateItem(
        counter.actorNow(),
        sugar,
        named('Sugar 1kg pack'),
      );
      await counter.sync.syncNow();

      for (final phone in [master, counter]) {
        final row = await phone.database
            .customSelect(
              'SELECT name FROM items WHERE id = ?',
              variables: [Variable<String>(sugar)],
            )
            .getSingle();
        expect(row.read<String>('name'), 'Sugar 1kg pack');
      }
    });

    test('a second sync with nothing new moves nothing', () async {
      await sell(counter, 1);
      await counter.sync.syncNow();
      const outbox = 'SELECT COUNT(*) AS n FROM change_log';
      final before = (
        await count(master, outbox),
        await count(counter, outbox),
      );

      final again = await counter.sync.syncNow();
      expect(again.sent.applied, 0);
      expect(again.received.applied, 0);
      expect((
        await count(master, outbox),
        await count(counter, outbox),
      ), before);
    });

    test("what was done at a counter is in the master's activity log", () async {
      await sell(counter, 1);
      await counter.sync.syncNow();
      final counterId = (await counter.sync.devices())
          .singleWhere((d) => d.isThisDevice)
          .id;
      expect(
        await count(
          master,
          "SELECT COUNT(*) AS n FROM audit_log WHERE origin_device_id = '$counterId'",
        ),
        greaterThan(0),
      );
    });

    test(
      'a second counter gets the first one\'s sales through the master',
      () async {
        await sell(counter, 2);
        await counter.sync.syncNow();
        final third = await joined('Counter 3');
        addTearDown(third.close);

        expect(await stockOn(third), Qty.units(8));
        final bill = await sell(third, 1);
        expect(bill, contains('-C'));
        await third.sync.syncNow();
        await counter.sync.syncNow();
        expect(await stockOn(counter), Qty.units(7));
      },
    );

    test('two items given the same barcode apart are both kept', () async {
      final firm = (await master.queries.currentFirm())!;
      final unit = (await master.queries.units(firm.id)).first;
      await master.catalogue.addItem(
        master.actorNow(),
        ItemDraft(
          name: 'Tapal 95g',
          barcode: '8964000123',
          baseUnitId: unit.id,
          saleRate: Rate.rupees(250),
        ),
      );
      await counter.catalogue.addItem(
        counter.actorNow(),
        ItemDraft(
          name: 'Lipton 95g',
          barcode: '8964000123',
          baseUnitId: unit.id,
          saleRate: Rate.rupees(260),
        ),
      );
      final report = await counter.sync.syncNow();

      expect(report.conflicts, 2, reason: 'one each way');
      expect(await master.sync.conflicts(), 1);
      final kept = await master.database
          .customSelect(
            "SELECT name, barcode FROM items WHERE name LIKE '%95g'",
          )
          .get();
      expect(kept, hasLength(2));
      expect(
        kept
            .singleWhere((r) => r.read<String>('name') == 'Tapal 95g')
            .read<String>('barcode'),
        '8964000123',
      );

      // The clash is listed by name, and once looked at it is cleared.
      final clashes = await master.sync.clashes();
      expect(clashes.single.label, startsWith('Lipton 95g'));
      expect(clashes.single.label, contains('8964000123~'));
      await master.sync.resolveClash(clashes.single.changeId);
      expect(await master.sync.conflicts(), 0);
      expect(await master.sync.clashes(), isEmpty);
    });

    test('staff PINs travel, so staff sign in at the counter', () async {
      await master.setPin(master.currentUser!.id, '1947');
      final bilal = await master.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2468',
      );
      final till = await joined('Counter 3');
      addTearDown(till.close);

      expect(till.isLocked, isTrue);
      expect(await till.signIn(bilal, '1111'), isFalse);
      expect(await till.signIn(bilal, '2468'), isTrue);
      expect(till.currentUser!.name, 'Bilal');
    });

    test('a wrong code does not let a phone join', () async {
      master.sync.openJoining();
      final phone = await openInMemoryServices(clock: clock);
      addTearDown(phone.close);
      await expectLater(
        phone.sync.join(
          host: '127.0.0.1',
          port: port,
          code: 'nope',
          label: 'X',
        ),
        throwsA(isA<SyncRefused>()),
      );
      expect(phone.isSetUp, isFalse);
    });
  });
}
