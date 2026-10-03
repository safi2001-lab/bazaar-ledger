import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Loyalty points through the one sale path, on a real database (M66).
///
/// 1 point per Rs 100 paid, 100 points worth Rs 50, half a bill at most:
/// the shop's rule in every test unless it says otherwise.
void main() {
  late AppServices shop;
  late String firmId;
  late String oil;
  late String pcs;
  late String cash;
  late String haji;

  setUp(() async {
    shop = await openInMemoryServices();
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(1000),
        openingStock: Qty.units(50),
        openingRate: Rate.rupees(800),
      ),
    );
    haji = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'Haji Sahib'),
    );
    await shop.loyalty.saveRule(const LoyaltyRule(from: '2000-01-01'));
  });

  tearDown(() => shop.close());

  SaleLineDraft oilLine(int qty) => SaleLineDraft(
    itemId: oil,
    itemName: 'Cooking Oil 5L',
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: pcs,
    unitCode: 'pcs',
    rate: Rate.rupees(1000),
  );

  Future<PostedSale> sell(
    int qty, {
    Money paid = Money.zero,
    LoyaltyRedemption? redeem,
    Money billDiscount = Money.zero,
    String? partyId,
  }) => shop.loyalty.postSaleFor(redeem: redeem)(
    shop.actorNow(),
    SaleDraft(
      partyId: partyId ?? haji,
      partyName: 'Haji Sahib',
      lines: [oilLine(qty)],
      billDiscount: billDiscount + (redeem?.value ?? Money.zero),
      tenders: [
        if (paid.isPositive)
          TenderDraft(paymentAccountId: cash, mode: 'cash', amount: paid),
      ],
    ),
  );

  Future<int> held() async => (await shop.loyalty.standingOf(haji)).outstanding;

  Future<void> expectBalanced() async {
    final row = await shop.database
        .customSelect(
          'SELECT SUM(debit_paisa) d, SUM(credit_paisa) c FROM journal_lines '
          'WHERE deleted_at_utc IS NULL',
        )
        .getSingle();
    expect(row.read<int>('d'), row.read<int>('c'));
  }

  Future<void> signInCashier() async {
    await shop.setPin(shop.currentUser!.id, '9999');
    final bilal = await shop.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2468',
    );
    expect(await shop.signIn(bilal, '2468'), isTrue);
  }

  group('loyalty points', () {
    test('are earned on what is paid: a cash bill at once, a bill on udhaar '
        'only as its udhaar comes in', () async {
      await sell(3, paid: const Money.rupees(3000));
      expect(await held(), 30);

      final udhaar = await sell(2);
      expect(await held(), 30, reason: 'nothing paid, nothing earned');
      await shop.recordReceipt(
        shop.actorNow(),
        ReceiptDraft(
          partyId: haji,
          amount: const Money.rupees(1250),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      expect(await held(), 30 + 12);
      final paper = (await shop.billPaper(udhaar.documentId))!.receipt;
      expect(
        paper.footerLines,
        contains(
          'Is bill par 12 points mile, 8 aur ada hone par - Kul 42 '
          'points',
        ),
        reason: 'the bills up to this one, as a reprint next month must',
      );
      await expectBalanced();
    });

    test('a walk-in earns nothing, and a shop that gives no points prints '
        'none', () async {
      final walkIn = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [oilLine(1)],
          tenders: [
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: const Money.rupees(1000),
            ),
          ],
        ),
      );
      final paper = (await shop.billPaper(walkIn.documentId))!.receipt;
      expect(paper.footerLines.where((l) => l.contains('points')), isEmpty);
    });

    test('are spent as a bill discount by a cashier, past their own 5%, '
        'into Discount Given, and the paper says so', () async {
      await sell(30, paid: const Money.rupees(30000));
      expect(await held(), 300);
      await signInCashier();

      // Rs 60 off a Rs 1,000 bill is 6%: past a cashier's own ceiling,
      // and theirs to give because it is the customer's points.
      final spent = await sell(
        1,
        paid: const Money.rupees(940),
        redeem: LoyaltyRedemption(
          partyId: haji,
          points: 120,
          value: const Money.rupees(60),
        ),
      );
      final bill = await shop.database
          .customSelect(
            'SELECT bill_discount_paisa d, total_paisa t FROM documents '
            'WHERE id = ?',
            variables: [Variable<String>(spent.documentId)],
          )
          .getSingle();
      expect(bill.read<int>('d'), 6000);
      expect(bill.read<int>('t'), 94000);
      // 300 held, 120 used, 9 earned on the Rs 940 paid.
      expect(await held(), 300 - 120 + 9);
      final discountGiven = await shop.database
          .customSelect(
            'SELECT SUM(jl.debit_paisa) - SUM(jl.credit_paisa) AS n '
            'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.document_id = ? AND a.system_key = 'discount_given'",
            variables: [Variable<String>(spent.documentId)],
          )
          .getSingle();
      expect(discountGiven.read<int>('n'), 6000);
      final paper = (await shop.billPaper(spent.documentId))!.receipt;
      expect(paper.footerLines, contains('120 points istemal hue (Rs 60.00)'));
      expect(
        paper.footerLines,
        contains('Is bill par 9 points mile - Kul 189 points'),
      );
      await expectBalanced();

      // A discount typed by the cashier is still theirs to give: 6% with
      // no points behind it is refused.
      await expectLater(
        sell(
          1,
          paid: const Money.rupees(940),
          billDiscount: const Money.rupees(60),
        ),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('are refused, and nothing written, past the customer\'s points, '
        'past half the bill, or at the wrong worth', () async {
      await sell(1, paid: const Money.rupees(1000));
      expect(await held(), 10);
      Future<int> bills() async =>
          (await shop.database
                  .customSelect(
                    "SELECT COUNT(*) n FROM documents WHERE doc_type = 'sale_invoice'",
                  )
                  .getSingle())
              .read<int>('n');

      await expectLater(
        sell(
          1,
          redeem: LoyaltyRedemption(
            partyId: haji,
            points: 20,
            value: const Money.rupees(10),
          ),
        ),
        throwsA(
          isA<LoyaltyRefused>().having(
            (r) => r.problem,
            'problem',
            LoyaltyProblem.notEnough,
          ),
        ),
      );
      await sell(20, paid: const Money.rupees(20000));
      await expectLater(
        sell(
          1,
          redeem: LoyaltyRedemption(
            partyId: haji,
            points: 120,
            value: const Money.rupees(60),
          ),
          billDiscount: const Money.rupees(900),
        ),
        throwsA(
          isA<LoyaltyRefused>().having(
            (r) => r.problem,
            'problem',
            LoyaltyProblem.overCap,
          ),
        ),
      );
      await expectLater(
        sell(
          1,
          redeem: LoyaltyRedemption(
            partyId: haji,
            points: 100,
            value: const Money.rupees(100),
          ),
        ),
        throwsA(
          isA<LoyaltyRefused>().having(
            (r) => r.problem,
            'problem',
            LoyaltyProblem.mismatch,
          ),
        ),
      );
      expect(await bills(), 2);
      expect(
        await shop.database
            .customSelect(
              'SELECT COUNT(*) n FROM settings WHERE setting_key LIKE '
              "'loyalty.redeemed.%'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
    });

    test('a return takes back the points on what came back and gives back '
        'the points spent on it; a cancelled bill does both in full', () async {
      await sell(10, paid: const Money.rupees(10000));
      expect(await held(), 100);
      final spent = await sell(
        2,
        paid: const Money.rupees(1960),
        redeem: LoyaltyRedemption(
          partyId: haji,
          points: 80,
          value: const Money.rupees(40),
        ),
      );
      expect(await held(), 100 - 80 + 19);

      final line =
          (await shop.database
                  .customSelect(
                    'SELECT id FROM document_lines WHERE document_id = ?',
                    variables: [Variable<String>(spent.documentId)],
                  )
                  .getSingle())
              .read<String>('id');
      await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: spent.documentId,
          lines: [ReturnLineDraft(documentLineId: line, qty: Qty.units(1))],
          reason: 'Seal was broken',
          refundNow: const Money.rupees(980),
          paymentAccountId: cash,
        ),
      );
      // Half the goods back: 9 of the 19 earned stay (Rs 980 kept), and
      // half the 80 spent come back.
      expect(await held(), 100 - 40 + 9);

      final other = await sell(
        1,
        paid: const Money.rupees(980),
        redeem: LoyaltyRedemption(
          partyId: haji,
          points: 40,
          value: const Money.rupees(20),
        ),
      );
      expect(await held(), 69 - 40 + 9);
      await shop.voidDocument(
        shop.actorNow(),
        documentId: other.documentId,
        reason: 'Wrong customer',
      );
      expect(await held(), 69);
      final standing = await shop.loyalty.standingOf(haji);
      expect(standing.redeemed, 40);
      await expectBalanced();
    });

    test(
      'switched off, a bill earns nothing from then on and keeps every '
      "point earned, the morning's included; points cannot be used",
      () async {
        await sell(5, paid: const Money.rupees(5000));
        await shop.loyalty.saveRule(
          const LoyaltyRule(from: '2000-01-01', isOn: false),
        );
        await sell(5, paid: const Money.rupees(5000));
        expect(await held(), 50, reason: 'the first bill keeps its points');
        final rules = await shop.loyalty.rules();
        expect(rules.versions.map((v) => v.isOn), [true, false]);
        await expectLater(
          sell(
            1,
            redeem: LoyaltyRedemption(
              partyId: haji,
              points: 10,
              value: const Money.rupees(5),
            ),
          ),
          throwsA(isA<LoyaltyRefused>()),
        );
      },
    );
  });

  group('a customer\'s own prices', () {
    test('are kept one row per customer, taken off by setting nothing, and '
        'set only by whoever may see costs', () async {
      await shop.loyalty.setPartyPrice(haji, oil, Rate.rupees(950));
      expect(
        (await shop.loyalty.pricesOf(haji)).rateFor(oil),
        Rate.rupees(950),
      );
      final list = await shop.loyalty.priceListOf(haji);
      expect(list.single.item.name, 'Cooking Oil 5L');
      await shop.loyalty.setPartyPrice(haji, oil, null);
      expect((await shop.loyalty.pricesOf(haji)).isEmpty, isTrue);

      await signInCashier();
      await expectLater(
        shop.loyalty.setPartyPrice(haji, oil, Rate.rupees(900)),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('the margin at the counter', () {
    test('costs are read only by whoever may see them, and the owner can '
        'turn the figure off', () async {
      expect(await shop.loyalty.marginShown(), isTrue);
      expect(await shop.loyalty.counterCosts([oil]), {oil: Rate.rupees(800)});
      await shop.loyalty.setMarginShown(shown: false);
      expect(await shop.loyalty.marginShown(), isFalse);
      await shop.loyalty.setMarginShown(shown: true);

      await signInCashier();
      expect(await shop.loyalty.marginShown(), isFalse);
      await expectLater(
        shop.loyalty.counterCosts([oil]),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });
}
