import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The mobile-shop pack (M50) against a real database: a phone kept by both
/// its IMEIs and refused when one is mistyped; its story from the delivery
/// to the bill, with its warranty and what PTA said; a used phone bought
/// over the counter with the seller's CNIC, on the shelf and in the
/// register; and a phone sold on qist, its instalments falling due on the
/// khata one by one and paid oldest first. The books balance after each.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftUdhaarQueries udhaar;
  late DriftMobileReads mobile;
  late DriftMobileWriter writer;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase sell;
  late RecordPurchaseUseCase buy;
  late RecordReceiptUseCase receive;
  late String pcs;
  late String cash;
  late String distributor;
  late String phoneItem;

  // Fifteen digits each, every one with the right check digit.
  const imeiA = '356938035643809';
  const imeiA2 = '356938035643817';
  const imeiB = '861234056789012';
  const imeiC = '352098765432107';
  const mistyped = '356938035643808';

  /// The shop on [day], at nine in the morning PKT.
  ActorContext on(String day) {
    final d = BusinessDate(day);
    return firm.actorAt(DateTime.utc(d.year, d.month, d.day, 4));
  }

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 1, 4));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Hafeez Centre Mobiles',
      ownerName: 'Bilal Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    udhaar = DriftUdhaarQueries(db);
    mobile = DriftMobileReads(db);
    writer = DriftMobileWriter(runner);
    catalogue = DriftCatalogueWriter(runner);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    distributor = await catalogue.addParty(
      on('2026-09-01'),
      const PartyDraft(name: 'Hall Road Distributors', partyType: 'supplier'),
    );
    phoneItem = await catalogue.addItem(
      on('2026-09-01'),
      ItemDraft(
        name: 'Samsung A15',
        baseUnitId: pcs,
        saleRate: Rate.rupees(60000),
        tracksSerial: true,
        warranty: const ItemWarranty(months: 12, kind: WarrantyKind.brand),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<PostedPurchase> receivePhones(
    String day,
    List<PhoneUnitDraft> phones, {
    int cost = 50000,
  }) => buy(
    on(day),
    PurchaseDraft(
      partyId: distributor,
      lines: [
        PurchaseLineDraft(
          itemId: phoneItem,
          itemName: 'Samsung A15',
          qty: Qty.units(phones.length),
          baseQty: Qty.units(phones.length),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(cost),
          phones: phones,
        ),
      ],
    ),
  );

  Future<String> lotOf(String imei) async =>
      (await db
              .customSelect(
                'SELECT id FROM stock_lots WHERE serial = ?',
                variables: [Variable<String>(imei)],
              )
              .getSingle())
          .read<String>('id');

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<void> booksBalance() async {
    final sums = await db
        .customSelect(
          'SELECT COALESCE(SUM(debit_paisa), 0) AS d, '
          'COALESCE(SUM(credit_paisa), 0) AS c FROM journal_lines '
          'WHERE deleted_at_utc IS NULL',
        )
        .getSingle();
    expect(sums.read<int>('d'), sums.read<int>('c'), reason: 'the books');
    final health = await db.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  }

  /// A phone sold to [partyId] on [day], [down] paid in cash and the rest
  /// on qist when [plan] is given.
  Future<PostedSale> sellPhone(
    String day,
    String imei, {
    String? partyId,
    int price = 60000,
    int down = 0,
    int markup = 0,
    QistPlanDraft? plan,
  }) async => sell(
    on(day),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: phoneItem,
          itemName: 'Samsung A15',
          qty: Qty.one,
          baseQty: Qty.one,
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(price),
          lotId: await lotOf(imei),
        ),
      ],
      tenders: [
        if (down > 0)
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: Money.rupees(down),
          ),
      ],
      extraCharges: Money.rupees(markup),
      qist: plan,
    ),
  );

  Future<String> customer(String name) =>
      catalogue.addParty(on('2026-09-01'), PartyDraft(name: name));

  group('the IMEI', () {
    test(
      'a mistyped IMEI is refused in words, and nothing is written',
      () async {
        await expectLater(
          receivePhones('2026-09-02', const [PhoneUnitDraft(imei1: mistyped)]),
          throwsA(
            isA<ImeiRefused>()
                .having(
                  (e) => e.problem.kind,
                  'kind',
                  ImeiProblemKind.checkDigit,
                )
                .having((e) => e.problem.expectedLast, 'should end in', 9)
                .having((e) => e.toString(), 'words', contains('mistyped')),
          ),
        );
        await expectLater(
          receivePhones('2026-09-02', const [
            PhoneUnitDraft(imei1: imeiA, imei2: '86123405678901'),
          ]),
          throwsA(
            isA<ImeiRefused>().having(
              (e) => e.problem.kind,
              'kind',
              ImeiProblemKind.wrongLength,
            ),
          ),
          reason: 'IMEI 2 is checked as IMEI 1 is',
        );
        expect(await count('stock_lots'), 0);
        expect(
          await count('documents'),
          0,
          reason: 'refused before the delivery was written',
        );
      },
    );

    test('a dual-SIM phone comes in by both IMEIs, and either finds it, in '
        'part or whole', () async {
      await receivePhones('2026-09-02', const [
        PhoneUnitDraft(imei1: imeiA, imei2: imeiA2, pta: PtaStatus.approved),
        PhoneUnitDraft(imei1: imeiB),
      ]);
      final byTail = await mobile.findPhones(firm.firmId, '43809');
      expect(byTail.single.imei1, imeiA);
      expect(byTail.single.imei2, imeiA2);
      expect(byTail.single.pta, PtaStatus.approved);
      expect(byTail.single.ptaCheckedOn?.value, '2026-09-02');
      expect(byTail.single.onHand, isTrue);
      final bySecond = await mobile.findPhones(firm.firmId, '35-6438-17');
      expect(bySecond.single.imei1, imeiA, reason: 'IMEI 2 finds it too');
      // At the counter, the scanner reads whichever barcode is on top.
      final scanned = await queries.serialOnHand(firm.firmId, imeiA2);
      expect(scanned?.lotNo, imeiA);
      expect(
        (await mobile.findPhones(firm.firmId, imeiB)).single.pta,
        PtaStatus.unknown,
      );
    });

    test(
      'one IMEI is one phone: a number already in the shop is refused',
      () async {
        await receivePhones('2026-09-02', const [
          PhoneUnitDraft(imei1: imeiA, imei2: imeiA2),
        ]);
        await expectLater(
          receivePhones('2026-09-03', const [PhoneUnitDraft(imei1: imeiA2)]),
          throwsA(isA<StockRefused>()),
        );
        await expectLater(
          receivePhones('2026-09-03', const [
            PhoneUnitDraft(imei1: imeiB, imei2: imeiB),
          ]),
          throwsA(
            isA<ImeiRefused>().having(
              (e) => e.problem.kind,
              'kind',
              ImeiProblemKind.sameAsFirst,
            ),
          ),
        );
        expect(await count('stock_lots'), 1);
      },
    );
  });

  group("a phone's story", () {
    test('says where it came from, who bought it on which bill, and its '
        'warranty, and the bill prints all of it', () async {
      await receivePhones('2026-09-02', const [
        PhoneUnitDraft(imei1: imeiA, imei2: imeiA2, pta: PtaStatus.approved),
      ]);
      final ayesha = await customer('Ayesha Bibi');
      final sale = await sellPhone(
        '2026-10-03',
        imeiA,
        partyId: ayesha,
        down: 60000,
      );
      final lotId = await lotOf(imeiA);
      await writer.recordWarrantyClaim(
        on('2026-12-01'),
        lotId,
        'Screen flickers; sent to the Samsung centre',
      );

      final story = (await mobile.phoneStory(firm.firmId, lotId))!;
      expect(story.events.map((e) => e.kind), [
        PhoneEventKind.bought,
        PhoneEventKind.sold,
      ]);
      final bought = story.events.first;
      expect(bought.partyName, 'Hall Road Distributors');
      expect(bought.on.value, '2026-09-02');
      expect(bought.amount, Money.rupees(50000));
      final sold = story.events.last;
      expect(sold.partyName, 'Ayesha Bibi');
      expect(sold.docNo, sale.docNo);
      expect(sold.amount, Money.rupees(60000));
      expect(sold.warrantyUntil?.value, '2027-10-03');
      expect(story.warrantyKind, WarrantyKind.brand);
      expect(story.unit.onHand, isFalse);
      expect(story.inWarrantyOn(BusinessDate('2027-10-03')), isTrue);
      expect(story.inWarrantyOn(BusinessDate('2027-10-04')), isFalse);
      expect(story.claims.single.note, contains('Samsung centre'));
      expect(story.claims.single.on.value, '2026-12-01');

      // A cashier, who may not see costs, reads the story without it.
      final blind = (await mobile.phoneStory(
        firm.firmId,
        lotId,
        withCosts: false,
      ))!;
      expect(blind.events.first.amount, isNull);

      final paper = (await queries.receiptFor(firm.firmId, sale.documentId))!;
      expect(paper.lines.single.details, [
        'IMEI 1: $imeiA',
        'IMEI 2: $imeiA2',
        'Warranty till 3 Oct 2027',
        'PTA Approved',
      ]);
      await booksBalance();
    });

    test('what PTA says is written down by hand, with the day', () async {
      await receivePhones('2026-09-02', const [PhoneUnitDraft(imei1: imeiB)]);
      final lotId = await lotOf(imeiB);
      await writer.setPta(on('2026-09-05'), lotId, PtaStatus.nonCompliant);
      final unit = (await mobile.phoneUnit(firm.firmId, lotId))!;
      expect(unit.pta, PtaStatus.nonCompliant);
      expect(unit.pta!.mayBeBlocked, isTrue);
      expect(unit.ptaCheckedOn?.value, '2026-09-05');
      await writer.setImei2(on('2026-09-05'), lotId, imeiC);
      expect((await mobile.phoneUnit(firm.firmId, lotId))!.imei2, imeiC);
      await expectLater(
        writer.setImei2(on('2026-09-05'), lotId, mistyped),
        throwsA(isA<ImeiRefused>()),
      );
      expect(ptaCheckSms(imeiB).toString(), 'sms:8484?body=$imeiB');
    });
  });

  group('a used phone bought over the counter', () {
    Future<({String documentId, String docNo, String partyId, String lotId})>
    buyUsed(
      String day, {
      String imei = imeiC,
      String seller = 'Kashif Mehmood',
      String cnic = '35202-1234567-1',
      int price = 18000,
    }) => writer.buyUsedPhone(
      on(day),
      UsedPhoneBuyDraft(
        sellerName: seller,
        sellerCnic: cnic,
        sellerPhone: '0300-1234567',
        conditionNote: 'Back cracked, no box',
        itemId: phoneItem,
        itemName: 'Samsung A15',
        unitId: pcs,
        unitCode: 'pcs',
        phone: PhoneUnitDraft(imei1: imei, pta: PtaStatus.approved),
        price: Money.rupees(price),
        paymentAccountId: cash,
      ),
      purchase: (sameTransaction, partyId) =>
          RecordPurchaseUseCase(writer: sameTransaction)(
            on(day),
            PurchaseDraft(
              partyId: partyId,
              paid: Money.rupees(price),
              paymentAccountId: cash,
              lines: [
                PurchaseLineDraft(
                  itemId: phoneItem,
                  itemName: 'Samsung A15',
                  qty: Qty.one,
                  baseQty: Qty.one,
                  unitId: pcs,
                  unitCode: 'pcs',
                  rate: Rate.rupees(price),
                  phones: [
                    PhoneUnitDraft(imei1: imei, pta: PtaStatus.approved),
                  ],
                ),
              ],
            ),
          ),
    );

    test('lands in stock by its IMEI and in the register with the seller '
        'CNIC, the cash out of the drawer, and the books balance', () async {
      final bought = await buyUsed('2026-09-10');

      final found = (await mobile.findPhones(firm.firmId, imeiC)).single;
      expect(found.onHand, isTrue);
      expect(found.lotId, bought.lotId);

      final register = await mobile.usedPhonesBought(firm.firmId);
      final row = register.single;
      expect(row.seller.name, 'Kashif Mehmood');
      expect(row.seller.cnic, '3520212345671');
      expect(row.seller.phone, '0300-1234567');
      expect(row.seller.conditionNote, 'Back cracked, no box');
      expect(row.imei1, imeiC);
      expect(row.pta, PtaStatus.approved);
      expect(row.price, Money.rupees(18000));
      expect(row.on.value, '2026-09-10');

      final seller = (await queries.partyById(firm.firmId, bought.partyId))!;
      expect(seller.name, 'Kashif Mehmood');
      final party = await db
          .customSelect(
            'SELECT party_type, party_group, cnic FROM parties WHERE id = ?',
            variables: [Variable<String>(bought.partyId)],
          )
          .getSingle();
      expect(party.read<String>('party_type'), 'supplier');
      expect(party.read<String>('party_group'), 'Used phone sellers');
      expect(party.read<String>('cnic'), '35202-1234567-1');
      expect(seller.balance, Money.zero, reason: 'paid in full, in cash');

      final story = (await mobile.phoneStory(firm.firmId, bought.lotId))!;
      expect(story.seller?.cnic, '3520212345671');
      expect(story.events.single.kind, PhoneEventKind.bought);
      expect(story.events.single.amount, Money.rupees(18000));

      // Paid out of the drawer: the cash account is Rs 18,000 lighter.
      final drawer = await db
          .customSelect(
            'SELECT COALESCE(SUM(jl.credit_paisa - jl.debit_paisa), 0) AS out '
            'FROM journal_lines jl JOIN payment_accounts pa '
            '  ON pa.ledger_account_id = jl.account_id '
            'WHERE pa.id = ? AND jl.deleted_at_utc IS NULL',
            variables: [Variable<String>(cash)],
          )
          .getSingle();
      expect(drawer.read<int>('out'), Money.rupees(18000).inPaisa);
      await booksBalance();

      // The same seller, back with another phone, is the same supplier.
      final again = await buyUsed(
        '2026-09-20',
        imei: imeiB,
        seller: 'Kashif M.',
        cnic: '3520212345671',
      );
      expect(again.partyId, bought.partyId);
      expect(
        (await mobile.usedPhonesBought(firm.firmId)).first.seller.name,
        'Kashif M.',
        reason: 'the register keeps the name as said on the day',
      );
      expect(
        (await mobile.sellerByCnic(firm.firmId, '35202-1234567-1'))!.name,
        'Kashif M.',
      );
    });

    test('a seller with a CNIC not in form is refused, and nothing is '
        'written', () async {
      await expectLater(
        buyUsed('2026-09-10', cnic: '35202-12345'),
        throwsA(isA<UsedPhoneRefused>()),
      );
      await expectLater(
        buyUsed('2026-09-10', imei: mistyped),
        throwsA(isA<ImeiRefused>()),
      );
      expect(await count('used_phone_buys'), 0);
      expect(await count('documents'), 0);
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM parties WHERE cnic IS NOT NULL',
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
    });

    test('a phone sold and bought back comes into its own lot, and its '
        'story runs on', () async {
      await receivePhones('2026-09-02', const [PhoneUnitDraft(imei1: imeiC)]);
      final ayesha = await customer('Ayesha Bibi');
      await sellPhone('2026-09-05', imeiC, partyId: ayesha, down: 60000);
      final back = await buyUsed('2026-10-01', seller: 'Ayesha Bibi');
      expect(back.lotId, await lotOf(imeiC), reason: 'one lot, one phone');
      final story = (await mobile.phoneStory(firm.firmId, back.lotId))!;
      expect(story.events.map((e) => e.kind), [
        PhoneEventKind.bought,
        PhoneEventKind.sold,
        PhoneEventKind.bought,
      ]);
      expect(story.unit.onHand, isTrue);
      expect(story.seller?.name, 'Ayesha Bibi');
      await expectLater(
        buyUsed('2026-10-02'),
        throwsA(isA<StockRefused>()),
        reason: 'it is in the shop now, and cannot arrive twice',
      );
      await booksBalance();
    });
  });

  group('a phone sold on qist', () {
    late String rashid;

    setUp(() async {
      rashid = await customer('Rashid Ali');
      await receivePhones('2026-09-02', const [
        PhoneUnitDraft(imei1: imeiA, imei2: imeiA2, pta: PtaStatus.approved),
      ]);
    });

    /// Rs 60,000 phone with Rs 5,000 markup, Rs 10,000 down: Rs 55,000 in
    /// eleven instalments of Rs 5,000 on the 5th, from 5 November.
    Future<PostedSale> onQist() => sellPhone(
      '2026-10-03',
      imeiA,
      partyId: rashid,
      down: 10000,
      markup: 5000,
      plan: QistPlanDraft(
        count: 11,
        dueDay: 5,
        firstDue: BusinessDate('2026-11-05'),
        guarantor: const Guarantor(
          name: 'Tariq Ali',
          cnic: '35202-7654321-3',
          phone: '0321-7654321',
        ),
      ),
    );

    test('makes the schedule, and its instalments fall due on the khata one '
        'by one', () async {
      final sale = await onQist();
      final plan = (await mobile.qistPlanForBill(
        firm.firmId,
        sale.documentId,
      ))!;
      expect(plan.billTotal, Money.rupees(65000));
      expect(plan.downPayment, Money.rupees(10000));
      expect(plan.markup, Money.rupees(5000));
      expect(plan.financed, Money.rupees(55000));
      expect(plan.count, 11);
      expect(plan.instalments.first.dueOn.value, '2026-11-05');
      expect(plan.instalments[1].dueOn.value, '2026-12-05');
      expect(plan.instalments.last.dueOn.value, '2027-09-05');
      expect(
        plan.instalments.every((i) => i.amount == Money.rupees(5000)),
        isTrue,
      );
      expect(plan.guarantor?.cnic, '3520276543213');
      expect(plan.goods.single, 'Samsung A15 · $imeiA');

      // Not yet due: the bill is due on the first instalment's day, not
      // thirty days after it was made.
      final bills = await udhaar.billsDue(
        firm.firmId,
        rashid,
        asOfDateLocal: '2026-11-04',
      );
      expect(bills.single.dueDateLocal, '2026-11-05');
      expect(bills.single.outstanding, Money.rupees(55000));
      expect(bills.single.isOverdue, isFalse);
      expect(
        await udhaar.dueParties(firm.firmId, asOfDateLocal: '2026-11-04'),
        everyElement(
          isA<DueParty>().having((p) => p.isOverdue, 'overdue', isFalse),
        ),
      );

      // On the 5th the first instalment is due today, and only that.
      final onTheDay = (await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-11-05',
      )).single;
      expect(onTheDay.dueToday, Money.rupees(5000));
      expect(onTheDay.overdue, Money.zero);
      expect(onTheDay.openBills, 1);
      final card = await udhaar.udhaarToday(
        firm.firmId,
        asOfDateLocal: '2026-11-05',
      );
      expect(card.dueTodayCount, 1);
      expect(card.dueToday, Money.rupees(5000));

      // A day later it is overdue on the chase list, and the other ten are
      // not.
      final late = (await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-11-06',
      )).single;
      expect(late.overdue, Money.rupees(5000));
      expect(late.party.balance, Money.rupees(55000));
      expect(late.oldestDueLocal, '2026-11-05');
      final aging = await udhaar.dueAging(
        firm.firmId,
        asOfDateLocal: '2026-11-06',
      );
      expect(aging.overdue, Money.rupees(5000));
      expect(aging[DueBucket.notYetDue], Money.rupees(50000));
      await booksBalance();

      final paper = (await queries.receiptFor(firm.firmId, sale.documentId))!;
      expect(paper.extraChargesLabel, 'Qist markup');
      expect(paper.extraCharges, Money.rupees(5000));
      expect(
        paper.footerLines.first,
        'QIST: Rs 10,000.00 down, 11 x Rs 5,000.00',
      );
      expect(
        paper.footerLines,
        contains('Due on day 5 of each month, 5 Nov 2026 to 5 Sep 2027'),
      );
      expect(
        paper.footerLines,
        contains('Guarantor: Tariq Ali, CNIC 35202-7654321-3, 0321-7654321'),
      );
    });

    test('a receipt settles the oldest instalment first', () async {
      final sale = await onQist();
      await receive(
        on('2026-11-04'),
        ReceiptDraft(
          partyId: rashid,
          amount: Money.rupees(7000),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      final plan = (await mobile.qistPlanForBill(
        firm.firmId,
        sale.documentId,
      ))!;
      expect(plan.paid, Money.rupees(7000));
      final first = plan.standings[0];
      final second = plan.standings[1];
      expect(first.isPaid, isTrue);
      expect(second.paid, Money.rupees(2000));
      expect(second.left, Money.rupees(3000));
      expect(plan.standings[2].paid, Money.zero);

      final bills = await udhaar.billsDue(
        firm.firmId,
        rashid,
        asOfDateLocal: '2026-11-06',
      );
      expect(
        bills.single.dueDateLocal,
        '2026-12-05',
        reason: 'November is paid; December is the next one owed',
      );
      expect(bills.single.isOverdue, isFalse);
      final chase = (await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-12-06',
      )).single;
      expect(chase.overdue, Money.rupees(3000));
      expect(plan.overdueOn(BusinessDate('2026-12-06')), Money.rupees(3000));
      await booksBalance();
    });

    test('an overdue instalment reaches the chase list, and a plan closed '
        'early is due at once', () async {
      final sale = await onQist();
      final chase = await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2027-01-10',
      );
      expect(chase.single.party.id, rashid);
      expect(chase.single.overdue, Money.rupees(15000));
      expect(chase.single.daysOverdue, 66);

      final plan = (await mobile.qistPlanForBill(
        firm.firmId,
        sale.documentId,
      ))!;
      await writer.closeQistEarly(
        on('2027-01-10'),
        plan.id,
        note: 'Going abroad; pays the rest next week',
      );
      final closed = (await mobile.qistPlan(firm.firmId, plan.id))!;
      expect(closed.closedOn?.value, '2027-01-10');
      expect(
        closed.standingOn(BusinessDate('2027-01-11')),
        QistStanding.overdue,
      );
      final after = (await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2027-01-11',
      )).single;
      expect(after.overdue, Money.rupees(55000), reason: 'all of it, now');
      await expectLater(
        writer.closeQistEarly(on('2027-01-11'), plan.id),
        throwsA(isA<MobileRefused>()),
      );
    });

    test(
      'the SQL and the domain agree on what each instalment still owes',
      () async {
        final sale = await onQist();
        final plan = (await mobile.qistPlanForBill(
          firm.firmId,
          sale.documentId,
        ))!;
        var paid = 0;
        for (final amount in [3000, 2000, 7500, 12500, 30000]) {
          await receive(
            on('2026-11-01'),
            ReceiptDraft(
              partyId: rashid,
              amount: Money.rupees(amount),
              mode: 'cash',
              paymentAccountId: cash,
            ),
          );
          paid += amount;
          final rows = await db
              .customSelect(
                'SELECT due_on, owed FROM (${qistOwedSql()}) ORDER BY due_on',
              )
              .get();
          final domain = settleOldestFirst(
            plan.instalments,
            Money.rupees(paid),
          );
          expect(
            [for (final r in rows) Money.paisa(r.read<int>('owed'))],
            [for (final s in domain) s.left],
            reason: 'after Rs $paid',
          );
        }
      },
    );

    test('is refused without a customer, or with nothing left to pay', () async {
      await expectLater(
        sellPhone(
          '2026-10-03',
          imeiA,
          down: 10000,
          plan: QistPlanDraft(
            count: 6,
            dueDay: 5,
            firstDue: BusinessDate('2026-11-05'),
          ),
        ),
        // The sale's own rule says it first: a walk-in cannot owe.
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'words',
            contains('name the customer'),
          ),
        ),
      );
      await expectLater(
        sellPhone(
          '2026-10-03',
          imeiA,
          partyId: rashid,
          down: 60000,
          plan: QistPlanDraft(
            count: 6,
            dueDay: 5,
            firstDue: BusinessDate('2026-11-05'),
          ),
        ),
        throwsA(isA<QistRefused>()),
      );
      await expectLater(
        sellPhone(
          '2026-10-03',
          imeiA,
          partyId: rashid,
          down: 10000,
          plan: QistPlanDraft(
            count: 6,
            dueDay: 5,
            firstDue: BusinessDate('2026-10-03'),
          ),
        ),
        throwsA(isA<QistRefused>()),
        reason: 'what is paid on the day is the down payment',
      );
      expect(await count('qist_plans'), 0);
      expect(
        await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
    });
  });
}
