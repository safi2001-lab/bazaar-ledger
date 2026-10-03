import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/paper.dart';

/// The polish round beneath the screens (M54), against a real database: the
/// small things the milestones said they had left, each proved where the
/// books are written.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String ownerId;
  late String pcs;
  late String cash;
  late String soap;

  setUp(() async {
    // Saturday 3 October 2026, eleven in the morning in Lahore.
    clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    ownerId = shop.currentUser!.id;
    final units = await shop.queries.units(firmId);
    pcs = units.firstWhere((u) => u.code == 'pcs').id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    soap = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Lux Soap',
        baseUnitId: pcs,
        saleRate: const Rate.rupees(100),
        openingStock: Qty.units(100),
        openingRate: const Rate.rupees(60),
      ),
    );
  });

  tearDown(() => shop.close());

  SaleLineDraft soapLine(int qty, {bool free = false}) => SaleLineDraft(
    itemId: soap,
    itemName: 'Lux Soap',
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: pcs,
    unitCode: 'pcs',
    rate: free ? Rate.zero : const Rate.rupees(100),
    isFreeItem: free,
  );

  Future<String> customer(String name, {int? creditDays}) =>
      shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(name: name, partyType: 'customer', creditDays: creditDays),
      );

  /// [qty] soaps to [partyId], all of it on udhaar unless [paid] says.
  Future<PostedSale> sellSoap(
    String partyId,
    int qty, {
    Money paid = Money.zero,
    QistPlanDraft? qist,
  }) => shop.postSale(
    shop.actorNow(),
    SaleDraft(
      lines: [soapLine(qty)],
      partyId: partyId,
      tenders: [
        if (paid.isPositive)
          TenderDraft(paymentAccountId: cash, mode: 'cash', amount: paid),
      ],
      qist: qist,
    ),
  );

  Future<void> signInCashier() async {
    await shop.setPin(ownerId, '9999');
    final bilal = await shop.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2468',
    );
    expect(await shop.signIn(bilal, '2468'), isTrue);
  }

  group('a challan billed after its scheme changed (M43)', () {
    test('is billed as it was sent, by a cashier too, and never with more '
        'given free than the challan gave', () async {
      final rashid = await customer('Rashid Traders');
      await shop.saveItemScheme(
        ItemScheme(
          itemId: soap,
          bonus: BonusRule(buy: Qty.units(10), free: Qty.one),
        ),
      );
      final challan = await shop.issueChallan(
        shop.actorNow(),
        SaleDraft(
          lines: [soapLine(10), soapLine(1, free: true)],
          partyId: rashid,
          partyName: 'Rashid Traders',
        ),
      );
      // The scheme is taken off before the bill: today it gives nothing.
      await shop.saveItemScheme(ItemScheme(itemId: soap));
      await signInCashier();

      final sent = await shop.queries.challanBonusLines(firmId, challan.id);
      expect(sent.single.baseQty, Qty.one);
      expect(sent.single.isFreeItem, isTrue);

      // Nine paid and two free is eleven soaps, as the challan sent — and
      // one more free than it gave. Refused for the cashier.
      await expectLater(
        shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [soapLine(9), soapLine(2, free: true)],
            partyId: rashid,
            convertedFromId: challan.id,
          ),
        ),
        throwsA(isA<PermissionDenied>()),
      );

      final bill = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [soapLine(10), ...sent],
          partyId: rashid,
          convertedFromId: challan.id,
        ),
      );
      expect(bill.total, const Money.rupees(1000));
      expect(await shop.database.findLedgerImbalances(), isEmpty);
    });
  });

  group('a bill sent from its send sheet (M42 x M30)', () {
    test('is written on its history with how, who and when — in closed '
        'books and under Data Lock too, and by a cashier', () async {
      final aslam = await customer('Aslam Store');
      final bill = await sellSoap(aslam, 2);
      await shop.audit.closeBooksThrough(BusinessDate.now(clock));
      await shop.setPin(ownerId, '9999');
      await shop.audit.setDataLock(on: true);
      await signInCashier();
      clock.advance(const Duration(hours: 1));
      await shop.audit.recordShared(bill.documentId, SharedVia.whatsapp);
      clock.advance(const Duration(minutes: 5));
      await shop.audit.recordShared(bill.documentId, SharedVia.picture);

      final rows = await shop.database
          .customSelect(
            'SELECT action_code, summary FROM audit_log '
            "WHERE action_code LIKE 'SHARED_%' ORDER BY at_utc",
          )
          .get();
      expect(
        [for (final r in rows) r.read<String>('action_code')],
        ['SHARED_WHATSAPP', 'SHARED_PICTURE'],
      );
      expect(
        rows.first.read<String>('summary'),
        '${bill.docNo}: Shared on WhatsApp',
      );

      // The owner reads it on the bill's history, as Bilal's doing.
      expect(await shop.signIn(ownerId, '9999'), isTrue);
      final story = await shop.audit.history(
        RecordRef.document(bill.documentId),
      );
      final shared = [
        for (final e in story)
          if (SharedVia.ofAction(e.actionCode) != null) e,
      ];
      expect(
        [for (final e in shared) e.actionCode],
        ['SHARED_WHATSAPP', 'SHARED_PICTURE'],
      );
      expect(shared.first.who, 'Bilal');
      expect(await shop.database.findLedgerImbalances(), isEmpty);
    });
  });

  group('the paper behind a loan entry and a batch (M60)', () {
    test('is photographed onto the entry and the batch, kept small, and '
        'named by them in the recycle bin when taken off', () async {
      final bank = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'bank_transfer').id;
      final loan = await shop.loans.take(
        LoanDraft(
          lender: 'Meezan Bank',
          amount: const Money.rupees(500000),
          intoPaymentAccountId: bank,
          takenOn: BusinessDate.now(clock),
        ),
      );
      final entry = (await shop.loans.statement(loan)).lines.single;

      final panadol = await shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: 'Panadol 500',
          baseUnitId: pcs,
          saleRate: const Rate.rupees(2),
          tracksBatch: true,
        ),
      );
      final muller = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Muller Pharma', partyType: 'supplier'),
      );
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: muller,
          lines: [
            PurchaseLineDraft(
              itemId: panadol,
              itemName: 'Panadol 500',
              qty: Qty.units(100),
              baseQty: Qty.units(100),
              unitId: pcs,
              unitCode: 'pcs',
              rate: const Rate.rupees(1),
              batchNo: 'PN-2611',
              expiry: const BusinessDate('2027-06-30'),
            ),
          ],
        ),
      );
      final lot = (await shop.queries.lotsOnHand(
        firmId,
        itemId: panadol,
      )).single;

      Future<String> photograph(String table, String id, int shade) =>
          shop.photos.add(
            ownerTable: table,
            ownerId: id,
            kind: EntryPhotoKind.receipt,
            source: paper(shade),
            fileName: 'parchi-$shade.bmp',
          );
      final letter = await photograph('journal_entries', entry.entryId, 1);
      await photograph('stock_lots', lot.lotId, 2);

      final onLoan = await shop.photos.of('journal_entries', entry.entryId);
      expect(onLoan.single.addedBy, 'Malik Sahib');
      expect(onLoan.single.bytes.length, lessThan(EntryPhoto.maxBytes));
      expect(await shop.photos.of('stock_lots', lot.lotId), hasLength(1));

      await shop.photos.remove(letter);
      final binned = await shop.photos.removed();
      expect(binned.single.ownerLabel, entry.entryNo);
      expect(await shop.database.findLedgerImbalances(), isEmpty);
    });
  });

  group('a cheque handed over on the recovery round (M55 x M6)', () {
    test('becomes a cheque receipt on the khata in the round\'s one save, '
        'waits in Cheques in Hand, and is no cash to hand over', () async {
      final chequeAccount = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cheque').id;
      Future<String> owing(String name, int rupees) => shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(
          name: name,
          partyType: 'customer',
          openingBalance: Money.rupees(rupees),
        ),
      );
      final aslam = await owing('Aslam Karyana', 5000);
      final bilal = await owing('Bilal Store', 3000);
      final sheet = await shop.collections.makeSheet(
        SheetDraft(partyIds: [aslam, bilal], collector: 'Rafiq'),
      );
      final drawer = await shop.queries.cashInDrawer(firmId);
      final in15 = BusinessDate.now(clock).addDays(15);

      // A cheque with no number cannot be followed to the bank: refused,
      // and nothing of the round is written.
      await expectLater(
        shop.collections.recordReturn(sheet.id, {
          1: SheetMark(
            outcome: CollectionOutcome.paid,
            mode: 'cheque',
            paymentAccountId: chequeAccount,
          ),
          2: SheetMark(outcome: CollectionOutcome.paid, paymentAccountId: cash),
        }),
        throwsA(isA<CollectionRefused>()),
      );

      final round = await shop.collections.recordReturn(sheet.id, {
        1: SheetMark(
          outcome: CollectionOutcome.paid,
          mode: 'cheque',
          paymentAccountId: chequeAccount,
          chequeNo: '000451',
          chequeBank: 'HBL',
          chequeDateUtcMillis: chequeDueUtcMillis(in15),
        ),
        2: SheetMark(outcome: CollectionOutcome.paid, paymentAccountId: cash),
      });

      final rows = await shop.database
          .customSelect(
            'SELECT mode, status, cheque_no, cheque_bank, amount_paisa, notes '
            "FROM payments WHERE direction = 'in' ORDER BY amount_paisa DESC",
          )
          .get();
      expect(rows.first.read<String>('mode'), 'cheque');
      expect(rows.first.read<String>('status'), 'pending');
      expect(rows.first.read<String>('cheque_no'), '000451');
      expect(rows.first.read<String>('cheque_bank'), 'HBL');
      expect(rows.first.read<int>('amount_paisa'), 500000);
      expect(rows.first.read<String>('notes'), contains('Rafiq'));
      expect(round.receipts, hasLength(2));

      final inHand = await shop.queries.chequesInHand(firmId);
      expect(inHand.single.chequeNo, '000451');
      expect(inHand.single.due, in15);
      expect(
        (await shop.queries.partyById(firmId, aslam))!.balance,
        Money.zero,
      );
      // Rs 3,000 of cash to hand over; the cheque is not cash.
      expect(
        await shop.queries.cashInDrawer(firmId),
        drawer + const Money.rupees(3000),
      );
      expect(round.sheet.collected, const Money.rupees(8000));
      expect(round.sheet.cashToHandOver, const Money.rupees(3000));
      expect(round.sheet.lines.first.result!.chequeNo, '000451');
      expect(await shop.database.findLedgerImbalances(), isEmpty);
    });
  });

  group('expected collections this week (M35 x M38 x M50)', () {
    test('lists what falls due, the qist instalments and the promises of '
        'the next seven days, each customer once, with totals', () async {
      // Two weeks ago, on five days' terms: late since 25 September. And
      // today again, due on Thursday.
      clock.set(DateTime.utc(2026, 9, 20, 6));
      final dawood = await customer('Dawood Sons', creditDays: 5);
      await sellSoap(dawood, 5);
      clock.set(DateTime.utc(2026, 10, 3, 6));
      await sellSoap(dawood, 2);

      // Today, on five days' terms: due on Thursday 8 October.
      final aslam = await customer('Aslam Store', creditDays: 5);
      await sellSoap(aslam, 10);
      // On the shop's thirty days: not due until November — but he
      // promised Rs 1,500 for Tuesday.
      final bashir = await customer('Bashir Kiryana');
      await sellSoap(bashir, 20);
      await shop.udhaar.recordPromise(
        PromiseDraft(
          partyId: bashir,
          promisedFor: '2026-10-06',
          amount: const Money.rupees(1500),
        ),
      );
      // On qist: Rs 6,000 down on Rs 30,000, four of Rs 6,000 from the 7th.
      final chaudhry = await customer('Chaudhry Mobile');
      await sellSoap(
        chaudhry,
        300,
        paid: const Money.rupees(6000),
        qist: QistPlanDraft(
          count: 4,
          dueDay: 7,
          firstDue: const BusinessDate('2026-10-07'),
        ),
      );
      // A promise for after the week is not this week's.
      final ejaz = await customer('Ejaz Traders');
      await sellSoap(ejaz, 3);
      await shop.udhaar.recordPromise(
        PromiseDraft(partyId: ejaz, promisedFor: '2026-10-20'),
      );

      final table = await shop.reports.run(
        ReportKind.expectedCollections,
        firmId: firmId,
        period: ReportPeriod.day(BusinessDate.now(clock)),
        today: BusinessDate.now(clock),
      );
      final byName = {
        for (final r in table.rows)
          if (r.style != RowStyle.total) r.cells.first! as String: r.cells,
      };
      int col(String title) =>
          table.columns.indexWhere((c) => c.title == title);
      Money at(String name, String title) =>
          byName[name]![col(title)]! as Money;

      expect(byName.keys, [
        'Bashir Kiryana',
        'Chaudhry Mobile',
        'Aslam Store',
        'Dawood Sons',
      ], reason: 'the earliest day first, the larger first on a day');
      expect(at('Aslam Store', 'Falls due'), const Money.rupees(1000));
      expect(byName['Aslam Store']![col('First due')], '2026-10-08');
      expect(at('Bashir Kiryana', 'Falls due'), Money.zero);
      expect(at('Bashir Kiryana', 'Promised'), const Money.rupees(1500));
      expect(byName['Bashir Kiryana']![col('Promised for')], '2026-10-06');
      expect(at('Chaudhry Mobile', 'Falls due'), const Money.rupees(6000));
      expect(at('Chaudhry Mobile', 'Of it on qist'), const Money.rupees(6000));
      expect(at('Dawood Sons', 'Falls due'), const Money.rupees(200));
      expect(at('Dawood Sons', 'Late already'), const Money.rupees(500));
      expect(byName.containsKey('Ejaz Traders'), isFalse);

      final total = table.rows.last.cells;
      expect(total[col('Falls due')], const Money.rupees(7200));
      expect(total[col('Promised')], const Money.rupees(1500));
      expect(total[col('Expected')], const Money.rupees(8700));
      expect(total[col('Late already')], const Money.rupees(500));
      expect(table.summary.first.amount, const Money.rupees(8700));

      // Narrowed to one customer, it is theirs alone.
      final one = await shop.reports.run(
        ReportKind.expectedCollections,
        firmId: firmId,
        period: ReportPeriod.day(BusinessDate.now(clock)),
        today: BusinessDate.now(clock),
        filters: ReportFilters(partyId: bashir),
      );
      expect(one.rows.where((r) => r.style != RowStyle.total), hasLength(1));
    });
  });
}
