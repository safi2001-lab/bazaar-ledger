import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The bills that come round every week or month (M63), through the
/// services the screens use, against a real database and a clock the test
/// moves on.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String ownerId;
  late String pcs;
  late String milk;
  late String bread;
  late String hotel;
  late String canteen;

  setUp(() async {
    // Saturday 3 October 2026, mid-morning in Lahore.
    clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    ownerId = shop.currentUser!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    milk = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Doodh 1L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(220),
        wholesaleRate: Rate.rupees(200),
        openingStock: Qty.units(500),
        openingRate: Rate.rupees(150),
      ),
    );
    bread = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Double Roti',
        baseUnitId: pcs,
        saleRate: Rate.rupees(150),
        openingStock: Qty.units(5),
        openingRate: Rate.rupees(100),
      ),
    );
    hotel = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'Hotel Al-Madina', priceTier: PriceTier.wholesale),
    );
    canteen = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'School Canteen'),
    );
  });

  tearDown(() => shop.close());

  BusinessDate today() => BusinessDate.now(clock);

  void moveTo(String date) {
    final d = BusinessDate(date);
    clock.set(DateTime.utc(d.year, d.month, d.day, 6));
  }

  RecurringLine line(String item, String name, int qty, int rupees) =>
      RecurringLine(
        itemId: item,
        name: name,
        qty: Qty.units(qty),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  Future<RecurringBill> keep({
    required String party,
    required String name,
    required List<RecurringLine> lines,
    RepeatEvery every = const RepeatEvery.weekly(DateTime.monday),
    String start = '2026-10-04',
    RecurringMode mode = RecurringMode.automatic,
    RecurringPrices prices = RecurringPrices.today,
    Money billDiscount = Money.zero,
  }) async {
    final bill = RecurringBill(
      id: shop.recurring.newId(),
      partyId: party,
      partyName: name,
      lines: lines,
      every: every,
      startOn: BusinessDate(start),
      mode: mode,
      prices: prices,
      billDiscount: billDiscount,
    );
    await shop.recurring.save(bill);
    return (await shop.recurring.byId(bill.id))!;
  }

  Future<Money> owes(String party) async =>
      (await shop.queries.partyById(firmId, party))!.balance;

  Future<int> billsFor(String party) async =>
      (await shop.database
              .customSelect(
                "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice' "
                "AND status = 'posted' AND party_id = ?",
                variables: [Variable<String>(party)],
              )
              .getSingle())
          .read<int>('n');

  Future<void> booksBalance() async {
    final row = await shop.database
        .customSelect(
          'SELECT COALESCE(SUM(debit_paisa), 0) AS d, '
          'COALESCE(SUM(credit_paisa), 0) AS c FROM journal_lines '
          'WHERE deleted_at_utc IS NULL',
        )
        .getSingle();
    expect(row.read<int>('d'), row.read<int>('c'));
    expect(await shop.database.findLedgerImbalances(), isEmpty);
    expect((await shop.checkHealth()).findings, isEmpty);
  }

  group('repeating bills on the day', () {
    test('a weekly bill comes due on its day and not before', () async {
      await keep(
        party: canteen,
        name: 'School Canteen',
        lines: [line(bread, 'Double Roti', 2, 150)],
      );
      expect(await shop.recurring.due(), isEmpty, reason: 'Saturday');
      moveTo('2026-10-04');
      expect(await shop.recurring.due(), isEmpty, reason: 'Sunday');
      moveTo('2026-10-05');
      final due = await shop.recurring.due();
      expect(due, hasLength(1));
      expect(due.single.dates, [BusinessDate('2026-10-05')]);
      expect(due.single.missed, isFalse);
      expect(await billsFor(canteen), 0, reason: 'nothing made by itself');
    });

    test('made by itself, each is an udhaar bill at the day\'s prices, the '
        'khata rises exactly, the template moves on, and the books '
        'balance', () async {
      final bill = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 20, 220)],
        every: const RepeatEvery.daily(),
      );
      moveTo('2026-10-04');
      final due = await shop.recurring.due();
      expect(due.single.dates, [BusinessDate('2026-10-04')]);

      final out = await shop.recurring.makeEach([
        (bill: bill, forDate: due.single.latest),
      ]);
      expect(out.single.made, isTrue);
      // Wholesale is Rs 200 a litre: twenty is Rs 4,000, all on the khata.
      expect(out.single.posted!.total, const Money.rupees(4000));
      expect(out.single.posted!.paid, Money.zero);
      expect(await owes(hotel), const Money.rupees(4000));
      expect(await shop.recurring.due(), isEmpty);

      final kept = await shop.recurring.byId(bill.id);
      expect(kept!.doneThrough, BusinessDate('2026-10-04'));
      final history = await shop.recurring.history(bill.id);
      expect(history.single.docNo, out.single.posted!.docNo);
      expect(history.single.forDate, BusinessDate('2026-10-04'));
      expect(history.single.byItself, isTrue);
      await booksBalance();
    });

    test('a day already made is refused, and nothing of the second bill is '
        'written', () async {
      final bill = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 20, 220)],
        every: const RepeatEvery.daily(),
      );
      moveTo('2026-10-04');
      final first = await shop.recurring.make(bill, today());
      expect(first.made, isTrue);
      final again = await shop.recurring.make(bill, today());
      expect(again.made, isFalse);
      expect(
        again.refusal,
        isA<RecurringRefused>()
            .having((r) => r.problem, 'problem', RecurringProblem.alreadyMade)
            .having((r) => r.docNo, 'docNo', first.posted!.docNo),
      );
      expect(await billsFor(hotel), 1);
      expect(await owes(hotel), const Money.rupees(4000));
    });

    test('days the app was not opened are listed and asked about, and each '
        'answer does what it says', () async {
      final bill = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 10, 220)],
        every: const RepeatEvery.daily(),
      );
      // Shut from Sunday; opened on Wednesday.
      moveTo('2026-10-07');
      final due = (await shop.recurring.due()).single;
      expect(due.missed, isTrue);
      expect(due.dates, hasLength(4));
      expect(await billsFor(hotel), 0, reason: 'never made silently');

      // Only the latest: the earlier days let go, the last made.
      await shop.recurring.letGo(bill.id, due.dates[due.dates.length - 2]);
      final latest = await shop.recurring.make(
        (await shop.recurring.byId(bill.id))!,
        due.latest,
      );
      expect(latest.made, isTrue);
      expect(await billsFor(hotel), 1);
      expect(await shop.recurring.due(), isEmpty);

      // Shut again until Saturday: all of them, each its own bill dated
      // today and recorded for its own day.
      moveTo('2026-10-10');
      final again = (await shop.recurring.due()).single;
      expect(again.dates, hasLength(3));
      final all = await shop.recurring.makeEach([
        for (final d in again.dates) (bill: again.bill, forDate: d),
      ]);
      expect(all.every((o) => o.made), isTrue);
      expect(await billsFor(hotel), 4);
      expect(await owes(hotel), const Money.rupees(8000));
      final history = await shop.recurring.history(bill.id);
      expect(history.first.forDate, BusinessDate('2026-10-10'));
      expect(history[2].forDate, BusinessDate('2026-10-08'));
      expect(history[2].madeOn, BusinessDate('2026-10-10'));

      // And none: let go without a bill.
      moveTo('2026-10-12');
      expect((await shop.recurring.due()).single.dates, hasLength(2));
      await shop.recurring.letGo(bill.id, today());
      expect(await shop.recurring.due(), isEmpty);
      expect(await billsFor(hotel), 4);
      await booksBalance();
    });

    test('a paused bill never comes due, and once resumed the days it was '
        'paused through are not owed', () async {
      final bill = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 10, 220)],
        every: const RepeatEvery.daily(),
      );
      await shop.recurring.pause(bill.id);
      moveTo('2026-10-20');
      expect(await shop.recurring.due(), isEmpty);
      await shop.recurring.resume(bill.id);
      final due = await shop.recurring.due();
      expect(due.single.dates, [BusinessDate('2026-10-20')]);
      await shop.recurring.end(bill.id);
      moveTo('2026-11-20');
      expect(await shop.recurring.due(), isEmpty);
      expect((await shop.recurring.byId(bill.id))!.isEnded, isTrue);
    });
  });

  group('repeating bills keep the counter\'s rules', () {
    test('an item set to block stops that one bill and says why; the next '
        'is made', () async {
      await shop.catalogue.updateItem(
        shop.actorNow(),
        bread,
        ItemDraft(
          name: 'Double Roti',
          baseUnitId: pcs,
          saleRate: Rate.rupees(150),
          negativeStock: NegativeStock.block,
        ),
      );
      final short = await keep(
        party: canteen,
        name: 'School Canteen',
        lines: [line(bread, 'Double Roti', 50, 150)],
        every: const RepeatEvery.daily(),
      );
      final fine = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 5, 220)],
        every: const RepeatEvery.daily(),
      );
      moveTo('2026-10-04');
      final out = await shop.recurring.makeEach([
        (bill: short, forDate: today()),
        (bill: fine, forDate: today()),
      ]);
      expect(out.first.made, isFalse);
      expect(out.first.refusal, isA<ShelfRefused>());
      expect(out.last.made, isTrue);
      expect(await billsFor(canteen), 0);
      expect(
        (await shop.recurring.due()).single.bill.id,
        short.id,
        reason: 'still owed',
      );
    });

    test('a customer past their credit limit is held for the cashier\'s '
        'word, and made when it is given', () async {
      final limited = await shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(name: 'Dhaba', creditLimit: const Money.rupees(1000)),
      );
      final bill = await keep(
        party: limited,
        name: 'Dhaba',
        lines: [line(milk, 'Doodh 1L', 10, 220)],
        every: const RepeatEvery.daily(),
      );
      moveTo('2026-10-04');
      final held = await shop.recurring.make(bill, today());
      expect(held.held, isTrue);
      expect(held.overLimit!.limit, const Money.rupees(1000));
      expect(held.overLimit!.after, const Money.rupees(2200));
      expect(await billsFor(limited), 0);

      final made = await shop.recurring.make(bill, today(), confirmed: true);
      expect(made.made, isTrue);
      expect(await owes(limited), const Money.rupees(2200));
    });

    test(
      "a cashier's discount ceiling holds for a bill made by itself",
      () async {
        final bill = await keep(
          party: canteen,
          name: 'School Canteen',
          lines: [
            RecurringLine(
              itemId: milk,
              name: 'Doodh 1L',
              qty: Qty.units(10),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(220),
              discountBp: 2000,
            ),
          ],
          every: const RepeatEvery.daily(),
          prices: RecurringPrices.fixed,
        );
        await shop.setPin(ownerId, '9999');
        final bilal = await shop.addStaff(
          name: 'Bilal',
          role: Role.cashier,
          pin: '2468',
        );
        expect(await shop.signIn(bilal, '2468'), isTrue);
        moveTo('2026-10-04');
        final out = await shop.recurring.make(bill, today());
        expect(out.made, isFalse);
        expect(out.refusal, isA<PermissionDenied>());
        expect(await billsFor(canteen), 0);
      },
    );

    test('a role that may not sell can neither keep nor make one', () async {
      await shop.setPin(ownerId, '9999');
      final ali = await shop.addStaff(
        name: 'Ali',
        role: Role.accountant,
        pin: '1357',
      );
      expect(await shop.signIn(ali, '1357'), isTrue);
      expect(shop.recurring.mayUse, isFalse);
      expect(() => shop.recurring.all(), throwsA(isA<PermissionDenied>()));
    });
  });

  group('repeating bills from the counter', () {
    test(
      'a bill rung on the counter for its day moves the template on in '
      'the same commit; for another customer it is an ordinary bill',
      () async {
        final bill = await keep(
          party: hotel,
          name: 'Hotel Al-Madina',
          lines: [line(milk, 'Doodh 1L', 20, 220)],
          every: const RepeatEvery.daily(),
          mode: RecurringMode.remind,
        );
        moveTo('2026-10-04');
        SaleDraft draft(String party) => SaleDraft(
          partyId: party,
          lines: [
            SaleLineDraft(
              itemId: milk,
              itemName: 'Doodh 1L',
              qty: Qty.units(20),
              baseQty: Qty.units(20),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(200),
            ),
          ],
        );
        final mark = RecurringMark(
          billId: bill.id,
          forDate: today(),
          partyId: hotel,
          partyName: 'Hotel Al-Madina',
        );

        await shop.recurring.postSaleFor(mark)(shop.actorNow(), draft(canteen));
        expect((await shop.recurring.byId(bill.id))!.doneThrough, isNull);
        expect(await shop.recurring.due(), hasLength(1));

        final posted = await shop.recurring.postSaleFor(mark)(
          shop.actorNow(),
          draft(hotel),
        );
        expect((await shop.recurring.byId(bill.id))!.doneThrough, today());
        expect(await shop.recurring.due(), isEmpty);
        expect(
          (await shop.recurring.history(bill.id)).single.documentId,
          posted.documentId,
        );
        await booksBalance();
      },
    );

    test('a template is copied from a bill: a walk-in is refused, and an item '
        'hidden since is left off and said', () async {
      final cash = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cash').id;
      final walkIn = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          tenders: [
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: const Money.rupees(440),
            ),
          ],
          lines: [
            SaleLineDraft(
              itemId: milk,
              itemName: 'Doodh 1L',
              qty: Qty.units(2),
              baseQty: Qty.units(2),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(220),
            ),
          ],
        ),
      );
      expect(
        () => shop.recurring.startFromBill(walkIn.documentId),
        throwsA(
          isA<RecurringRefused>().having(
            (r) => r.problem,
            'problem',
            RecurringProblem.noCustomer,
          ),
        ),
      );

      final sale = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          partyId: hotel,
          lines: [
            for (final (item, name, qty) in [
              (milk, 'Doodh 1L', 20),
              (bread, 'Double Roti', 2),
            ])
              SaleLineDraft(
                itemId: item,
                itemName: name,
                qty: Qty.units(qty),
                baseQty: Qty.units(qty),
                unitId: pcs,
                unitCode: 'pcs',
                rate: Rate.rupees(150),
              ),
          ],
        ),
      );
      await shop.catalogue.archiveItem(shop.actorNow(), bread);
      final start = await shop.recurring.startFromBill(sale.documentId);
      expect(start.bill.partyId, hotel);
      expect(start.bill.lines.single.name, 'Doodh 1L');
      expect(start.bill.fromDocNo, sale.docNo);
      expect(start.leftOut.single.why, RecurringLeftOut.gone);
      expect(start.bill.startOn, BusinessDate('2026-10-04'));
      expect(start.bill.every, const RepeatEvery.weekly(DateTime.saturday));
    });

    test('every change is audited, and the template is one settings row '
        'whose id comes from the template', () async {
      final bill = await keep(
        party: hotel,
        name: 'Hotel Al-Madina',
        lines: [line(milk, 'Doodh 1L', 20, 220)],
      );
      await shop.recurring.save(
        bill.copyWith(lines: [line(milk, 'Doodh 1L', 25, 220)]),
      );
      await shop.recurring.pause(bill.id);
      final row = await shop.database
          .customSelect(
            "SELECT id FROM settings WHERE setting_key LIKE 'recurring.sale.%'",
          )
          .get();
      expect(row.single.read<String>('id'), recurringBillRowId(bill.id));
      final actions = await shop.database
          .customSelect(
            'SELECT action_code FROM audit_log WHERE action_code LIKE '
            "'RECURRING_%' ORDER BY at_utc, rowid",
          )
          .get();
      expect(
        [for (final a in actions) a.read<String>('action_code')],
        [
          'RECURRING_BILL_SET',
          'RECURRING_BILL_CHANGED',
          'RECURRING_BILL_PAUSED',
        ],
      );
      expect(
        (await shop.recurring.byId(bill.id))!.lines.single.qty,
        Qty.units(25),
      );
    });
  });
}
