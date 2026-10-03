import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_platform/pk_platform.dart' show InMemoryDraftStore, PinHasher;

/// Control the way a wholesaler runs it (M68) -- credit rules, days that
/// lock themselves, a shelf counted at random, and a cashier who only takes
/// the money -- against a real database, through the services every screen
/// uses.
void main() {
  late AppServices services;
  late FixedClock clock;
  late String owner;
  late String oil;
  late String sugar;
  late String cash;
  late String chequeAccount;
  late String rashid;

  // Saturday 3 October 2026, a quarter past two in the afternoon in Lahore.
  final start = DateTime.utc(2026, 10, 3, 9, 15);

  Future<void> seed(AppServices s) async {
    await s.setUpShop(
      shopName: 'Chishti Traders',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    owner = s.currentUser!.id;
    final firm = (await s.queries.currentFirm())!;
    final pcs = (await s.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    Future<String> item(String name, int rupees, int cost) =>
        s.catalogue.addItem(
          // On the shelf since the first of August, so bills dated back sell
          // stock that was there.
          s.actorNow().at(DateTime.utc(2026, 8, 1, 5)),
          ItemDraft(
            name: name,
            baseUnitId: pcs.id,
            saleRate: Rate.rupees(rupees),
            openingStock: Qty.units(200),
            openingRate: Rate.rupees(cost),
          ),
        );
    oil = await item('Cooking Oil 5L', 1000, 600);
    sugar = await item('Sugar 1kg', 150, 120);
    final accounts = await s.queries.paymentAccounts(firm.id);
    cash = accounts.firstWhere((a) => a.modeLabel == 'cash').id;
    chequeAccount = accounts.firstWhere((a) => a.modeLabel == 'cheque').id;
    rashid = await s.catalogue.addParty(
      s.actorNow(),
      const PartyDraft(
        name: 'Rashid Traders',
        partyType: 'customer',
        creditLimit: Money.rupees(5000),
      ),
    );
  }

  setUp(() async {
    clock = FixedClock(start);
    services = await openInMemoryServices(clock: clock);
    await seed(services);
  });

  tearDown(() => services.close());

  SaleLineDraft line(String item, int qty, {int rupees = 1000}) =>
      SaleLineDraft(
        itemId: item,
        itemName: item == oil ? 'Cooking Oil 5L' : 'Sugar 1kg',
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  /// A bill of [tins] tins of oil for [party], on udhaar unless [paid] or a
  /// [cheque] is given, as of [on] (mid-morning) or now.
  Future<PostedSale> sell({
    String? party,
    int tins = 1,
    Money? paid,
    String? cheque,
    String? on,
    String? convertedFromId,
    List<SaleLineDraft>? lines,
  }) {
    var actor = services.actorNow();
    if (on != null) {
      final d = BusinessDate(on);
      actor = actor.at(DateTime.utc(d.year, d.month, d.day, 5));
    }
    final total = Money.rupees(1000 * tins);
    return services.postSale(
      actor,
      SaleDraft(
        lines: lines ?? [line(oil, tins)],
        partyId: party,
        partyName: party == null ? null : 'Rashid Traders',
        convertedFromId: convertedFromId,
        tenders: [
          if (paid != null)
            TenderDraft(paymentAccountId: cash, mode: 'cash', amount: paid),
          if (cheque != null)
            TenderDraft(
              paymentAccountId: chequeAccount,
              mode: 'cheque',
              amount: total,
              chequeNo: cheque,
              chequeBank: 'Meezan',
              chequeDateUtc: start,
            ),
        ],
      ),
    );
  }

  Future<List<Map<String, Object?>>> rows(String sql, [List<String>? args]) =>
      services.database
          .customSelect(
            sql,
            variables: [
              for (final a in args ?? const <String>[]) Variable<String>(a),
            ],
          )
          .get()
          .then((r) => [for (final row in r) row.data]);

  Future<int> bills() async => (await rows(
    "SELECT id FROM documents WHERE doc_type = 'sale_invoice'",
  )).length;

  Future<void> expectBalanced() async {
    final health = await services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  }

  /// The PIN prompt, answered as the person at the phone would.
  List<ApprovalAsk> answerWith(List<ApprovalAnswer?> answers) {
    final asked = <ApprovalAsk>[];
    services.audit.prompt = (ask) async {
      asked.add(ask);
      return asked.length <= answers.length ? answers[asked.length - 1] : null;
    };
    return asked;
  }

  group('credit control', () {
    test('over the limit set to warn, the bill goes through and the log says '
        'it went past a warning', () async {
      await sell(party: rashid, tins: 4);
      final counter = await services.credit.atCounter(
        partyId: rashid,
        owed: const Money.rupees(2000),
      );
      expect(counter.breaches.single.rule, CreditRule.limit);
      expect(counter.blocks, isFalse);
      expect(counter.breaches.single.after, const Money.rupees(6000));

      final bill = await sell(party: rashid, tins: 2);
      final log = await rows(
        'SELECT entity_id, summary FROM audit_log '
        "WHERE action_code = '$creditWarningPassedAction'",
      );
      expect(log.single['entity_id'], bill.documentId);
      expect(log.single['summary'], contains('over the credit limit'));
      await expectBalanced();
    });

    test('over the limit set to block, udhaar is refused in words and nothing '
        'is written; cash is still taken', () async {
      await services.credit.setDefaults(
        const CreditDefaults(limitMode: CreditMode.block),
      );
      await sell(party: rashid, tins: 4);

      await expectLater(
        sell(party: rashid, tins: 2),
        throwsA(
          isA<ApprovalNeeded>()
              .having((e) => e.kind, 'kind', ApprovalKind.owner)
              .having((e) => e.detail, 'detail', isA<CreditVerdict>())
              .having(
                (e) => '$e',
                'words',
                allOf(
                  contains('Only the owner'),
                  contains('credit limit of Rs 5,000.00'),
                  contains('would owe Rs 6,000.00'),
                ),
              ),
        ),
      );
      expect(await bills(), 1);

      // Cash for the same goods is never refused.
      await sell(party: rashid, tins: 2, paid: const Money.rupees(2000));
      expect(await bills(), 2);
      await expectBalanced();
    });

    test(
      'more open bills than the rule allows is refused, and fewer pass',
      () async {
        await services.credit.setRules(
          rashid,
          const PartyCreditRules(
            maxOpenBills: 2,
            billsMode: CreditMode.block,
            limitMode: CreditMode.off,
          ),
        );
        await sell(party: rashid);
        await sell(party: rashid);
        final counter = await services.credit.atCounter(
          partyId: rashid,
          owed: const Money.rupees(1000),
        );
        expect(counter.blocking.single.rule, CreditRule.bills);
        expect(counter.blocking.single.count, 3);
        await expectLater(sell(party: rashid), throwsA(isA<ApprovalNeeded>()));
        expect(await bills(), 2);
      },
    );

    test('a bill older than the days allowed stops new udhaar, and paying it '
        'lifts the stop', () async {
      await services.credit.setDefaults(
        const CreditDefaults(
          limitMode: CreditMode.off,
          maxDays: 30,
          daysMode: CreditMode.block,
        ),
      );
      await sell(party: rashid, on: '2026-09-03');
      // Thirty days old today: still allowed.
      await sell(party: rashid);
      clock.advance(const Duration(days: 1));
      await expectLater(
        sell(party: rashid),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => '$e',
            'words',
            contains('a bill 31 days old unpaid, at most 30 days'),
          ),
        ),
      );

      await services.recordReceipt(
        services.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(1000),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      await sell(party: rashid);
      expect(await bills(), 3);
      await expectBalanced();
    });

    test('after a bounced cheque, udhaar and another cheque are refused until '
        'it is made good', () async {
      await services.credit.setDefaults(
        const CreditDefaults(
          limitMode: CreditMode.off,
          bounceMode: CreditMode.block,
        ),
      );
      await sell(party: rashid, tins: 3);
      final cheque = await services.recordReceipt(
        services.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(3000),
          mode: 'cheque',
          paymentAccountId: chequeAccount,
          chequeNo: '004512',
          chequeBank: 'Meezan',
          chequeDateUtcMillis: chequeDueUtcMillis(BusinessDate.now(clock)),
        ),
      );
      await services.cheques.bounce(
        services.actorNow(),
        cheque.paymentId,
        reason: 'Funds insufficient',
      );

      await expectLater(sell(party: rashid), throwsA(isA<ApprovalNeeded>()));
      await expectLater(
        sell(party: rashid, cheque: '004513'),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => '$e',
            'words',
            contains('1 cheque(s) bounced and Rs 3,000.00 still owed'),
          ),
        ),
      );
      // Cash is never refused.
      await sell(party: rashid, paid: const Money.rupees(1000));

      // Made good: the stop lifts.
      await services.recordReceipt(
        services.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(3000),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      await sell(party: rashid);
      expect(await bills(), 3);
      await expectBalanced();
    });

    test('the owner lets one bill past with their PIN and a reason, and the '
        'log says who and why', () async {
      await services.setPin(owner, '1947');
      final nadeem = await services.addStaff(
        name: 'Nadeem',
        role: Role.manager,
        pin: '2468',
      );
      await services.credit.setDefaults(
        const CreditDefaults(limitMode: CreditMode.block),
      );
      await sell(party: rashid, tins: 4);
      await services.lock();
      await services.signIn(nadeem, '2468');

      final asked = answerWith([
        ApprovalAnswer(userId: owner, pin: '1947', reason: '  '),
        ApprovalAnswer(userId: owner, pin: '0000', reason: 'Wedding order'),
        ApprovalAnswer(userId: owner, pin: '1947', reason: 'Wedding order'),
      ]);
      final bill = await sell(party: rashid, tins: 3);

      expect(asked, hasLength(3));
      expect(asked.first.needed.kind, ApprovalKind.owner);
      expect(asked.first.needsReason, isTrue);
      // Only the owner is offered: the manager ringing it may not.
      expect(asked.first.people.map((m) => m.name), ['Malik Sahib']);
      expect(asked[1].problem, ApprovalProblem.reasonNeeded);
      expect(asked[2].problem, ApprovalProblem.wrongPin);

      final log = await rows(
        'SELECT entity_id, summary, after_json, created_by FROM audit_log '
        "WHERE action_code = '$creditOverrideAction'",
      );
      expect(log.single['entity_id'], bill.documentId);
      expect(log.single['created_by'], nadeem);
      expect(log.single['summary'], contains('Malik Sahib'));
      expect(log.single['summary'], contains('Wedding order'));
      expect(log.single['after_json'], contains('"limit"'));

      // One bill, not the next: the next is asked again.
      answerWith([null]);
      await expectLater(sell(party: rashid), throwsA(isA<ApprovalNeeded>()));
      expect(await bills(), 2);
      await expectBalanced();
    });

    test(
      'a temporary limit stands till its day and lapses by itself',
      () async {
        await services.credit.setDefaults(
          const CreditDefaults(limitMode: CreditMode.block),
        );
        // Rs 50,000 till Friday the 9th, on a customer held to Rs 5,000.
        await services.credit.setRules(
          rashid,
          PartyCreditRules(
            tempLimit: const Money.rupees(50000),
            tempUntil: BusinessDate('2026-10-09'),
          ),
        );
        await sell(party: rashid, tins: 20);
        clock.set(DateTime.utc(2026, 10, 9, 9));
        await sell(party: rashid, tins: 20);
        expect(await bills(), 2);

        // Saturday: back to Rs 5,000, with nobody having to remember.
        clock.set(DateTime.utc(2026, 10, 10, 9));
        final counter = await services.credit.atCounter(
          partyId: rashid,
          owed: const Money.rupees(1000),
        );
        expect(counter.blocking.single.limit, const Money.rupees(5000));
        expect(counter.blocking.single.temporary, isFalse);
        await expectLater(sell(party: rashid), throwsA(isA<ApprovalNeeded>()));
        expect(
          (await services.credit.rulesOf(
            rashid,
          )).tempLapsedOn(BusinessDate.now(clock)),
          isTrue,
        );

        // Zoho's raise-limit-and-save, for today only.
        await services.credit.raiseForToday(rashid, const Money.rupees(41000));
        await sell(party: rashid);
        clock.set(DateTime.utc(2026, 10, 11, 9));
        await expectLater(sell(party: rashid), throwsA(isA<ApprovalNeeded>()));
        await expectBalanced();
      },
    );

    test('a customer\'s own rules stand over the shop\'s, and only the owner '
        'sets them', () async {
      await services.credit.setDefaults(
        const CreditDefaults(maxOpenBills: 1, billsMode: CreditMode.block),
      );
      await services.credit.setRules(
        rashid,
        const PartyCreditRules(noBillsRule: true, limitMode: CreditMode.off),
      );
      await sell(party: rashid);
      await sell(party: rashid);
      await sell(party: rashid, tins: 9);
      expect(await bills(), 3);
      final set = await rows(
        'SELECT summary FROM audit_log WHERE action_code IN '
        "('$creditDefaultsSetAction', '$partyCreditSetAction') ORDER BY at_utc",
      );
      expect(set, hasLength(2));

      await services.setPin(owner, '1947');
      final bilal = await services.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      await services.lock();
      await services.signIn(bilal, '1357');
      expect(services.credit.mayChange, isFalse);
      await expectLater(
        services.credit.setRules(rashid, PartyCreditRules.none),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('days that lock themselves', () {
    test('older than N days: the closing date moves on by itself each day, and '
        'the owner can still let one entry in', () async {
      await services.setPin(owner, '1947');
      await services.autoLock.setRule(
        const AutoLock(mode: AutoLockMode.olderThan, days: 2),
      );
      expect((await services.audit.locks()).closedThrough!.value, '2026-09-30');
      final kept = await rows(
        'SELECT summary, after_json FROM audit_log WHERE action_code = '
        "'BOOKS_CLOSED'",
      );
      expect(kept.single['summary'], contains('by themselves'));

      await expectLater(
        sell(on: '2026-09-30', paid: const Money.rupees(1000)),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => e.kind,
            'kind',
            ApprovalKind.closedBooks,
          ),
        ),
      );
      await sell(on: '2026-10-01', paid: const Money.rupees(1000));

      // A day later the 1st has closed too, with nobody touching anything.
      clock.advance(const Duration(days: 1));
      await expectLater(
        sell(on: '2026-10-01', paid: const Money.rupees(1000)),
        throwsA(isA<ApprovalNeeded>()),
      );
      expect((await services.audit.locks()).closedThrough!.value, '2026-10-01');

      // The owner lets one in, as with any closed day.
      answerWith([
        ApprovalAnswer(userId: owner, pin: '1947', reason: 'Late bill'),
      ]);
      await sell(on: '2026-10-01', paid: const Money.rupees(1000));
      expect(
        await rows(
          "SELECT id FROM audit_log WHERE action_code = 'CLOSED_BOOKS_OVERRIDDEN'",
        ),
        hasLength(1),
      );

      // The kept date catches up when the app is next opened (keep()).
      await services.autoLock.keep();
      final moves = await rows(
        "SELECT after_json FROM audit_log WHERE action_code = 'BOOKS_CLOSED' "
        'ORDER BY at_utc',
      );
      expect(moves.last['after_json'], contains('2026-10-01'));
      await expectBalanced();
    });

    test('at day close: the day counted is closed from the moment it is '
        'counted', () async {
      await services.autoLock.setRule(
        const AutoLock(mode: AutoLockMode.atDayClose),
      );
      await sell(paid: const Money.rupees(1000));
      await services.closeDay(
        services.actorNow(),
        counted: const Money.rupees(1000),
        note: '',
      );
      await expectLater(
        sell(paid: const Money.rupees(1000)),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => '$e',
            'words',
            contains('closed up to 2026-10-03'),
          ),
        ),
      );
      clock.advance(const Duration(days: 1));
      await sell(paid: const Money.rupees(1000));
      expect(await bills(), 2);
    });

    test('only the owner sets the rule, and days it has closed stay closed '
        'while it stands', () async {
      await services.autoLock.setRule(
        const AutoLock(mode: AutoLockMode.olderThan, days: 5),
      );
      await expectLater(
        services.audit.closeBooksThrough(BusinessDate('2026-09-20')),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        services.audit.closeBooksThrough(null),
        throwsA(isA<PermissionDenied>()),
      );
      await services.setPin(owner, '1947');
      final nadeem = await services.addStaff(
        name: 'Nadeem',
        role: Role.manager,
        pin: '2468',
      );
      await services.lock();
      await services.signIn(nadeem, '2468');
      await expectLater(
        services.autoLock.setRule(AutoLock.off),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('the random stock check', () {
    test('a check names N items, never one counted yesterday', () async {
      // Ten more items, a few of them sold this month.
      final firm = (await services.queries.currentFirm())!;
      final pcs = (await services.queries.units(
        firm.id,
      )).firstWhere((u) => u.code == 'pcs');
      for (var i = 0; i < 10; i++) {
        await services.catalogue.addItem(
          services.actorNow(),
          ItemDraft(
            name: 'Item $i',
            baseUnitId: pcs.id,
            saleRate: Rate.rupees(100),
            openingStock: Qty.units(10),
            openingRate: Rate.rupees(80),
          ),
        );
      }
      await services.stockChecks.setRule(const StockCheckRule(size: 4));
      final first = await services.stockChecks.pick();
      expect(first.lines, hasLength(4));
      expect(first.lines.map((l) => l.itemId).toSet(), hasLength(4));

      clock.advance(const Duration(days: 1));
      final second = await services.stockChecks.pick();
      expect(
        second.lines
            .map((l) => l.itemId)
            .toSet()
            .intersection(first.lines.map((l) => l.itemId).toSet()),
        isEmpty,
      );
      // An item picked the day before yesterday may come round again.
      expect(await services.stockChecks.history(), hasLength(2));
    });

    test('counts are kept against the books as they stood, and the owner\'s '
        'approval posts the differences as Random check', () async {
      await services.stockChecks.setRule(
        const StockCheckRule(size: 2, daily: true),
      );
      final check = (await services.stockChecks.today())!;
      expect({for (final l in check.lines) l.itemId}, {oil, sugar});
      // Counting writes nothing to the books.
      final ledgerBefore = await rows('SELECT id FROM stock_ledger');

      await services.stockChecks.count(check.id, oil, Qty.units(197));
      // A tin sold between the count and the approval is gone from both.
      await sell(paid: const Money.rupees(1000));
      final counted = await services.stockChecks.count(
        check.id,
        sugar,
        Qty.units(201),
      );
      expect(counted.status, StockCheckStatus.counted);
      expect(counted.differing, hasLength(2));
      expect(
        await rows('SELECT id FROM stock_ledger'),
        hasLength(ledgerBefore.length + 1),
      );

      final posted = await services.stockChecks.post(check.id);
      expect(posted.status, StockCheckStatus.posted);
      final moves = await rows(
        'SELECT item_id, qty_delta_thousandths, value_delta_paisa, txn_type '
        "FROM stock_ledger WHERE reason = '$stockCheckReason' ORDER BY item_id",
      );
      expect(moves, hasLength(2));
      final byItem = {for (final m in moves) m['item_id']: m};
      expect(byItem[oil]!['qty_delta_thousandths'], -3000);
      expect(byItem[oil]!['value_delta_paisa'], -180000);
      expect(byItem[oil]!['txn_type'], 'adjustment');
      expect(byItem[sugar]!['qty_delta_thousandths'], 1000);
      // Oil: 200 opening, 1 sold, 3 missing.
      final shelf = await rows(
        'SELECT SUM(qty_delta_thousandths) AS q FROM stock_ledger '
        'WHERE item_id = ?',
        [oil],
      );
      expect(shelf.single['q'], 196000);
      expect(posted.shortValue, const Money.rupees(1800));
      expect(posted.overValue, const Money.rupees(120));

      final months = await services.stockChecks.shrinkage();
      expect(months.single.month, '2026-10');
      expect(months.single.net, const Money.rupees(1680));
      // Today's check is done; a daily rule does not pick another today.
      expect(await services.stockChecks.today(), isNull);
      await expectBalanced();
    });

    test('a cashier posts a check only with the owner\'s PIN', () async {
      await services.setPin(owner, '1947');
      final bilal = await services.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      await services.stockChecks.setRule(const StockCheckRule(size: 1));
      await services.lock();
      await services.signIn(bilal, '1357');
      final check = await services.stockChecks.pick();
      final item = check.lines.single.itemId;
      await services.stockChecks.count(check.id, item, Qty.units(190));

      await expectLater(
        services.stockChecks.post(check.id),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => e.kind,
            'kind',
            ApprovalKind.owner,
          ),
        ),
      );
      expect(
        await rows(
          "SELECT id FROM stock_ledger WHERE reason = '$stockCheckReason'",
        ),
        isEmpty,
      );
      final asked = answerWith([
        ApprovalAnswer(userId: owner, pin: '1947', reason: 'Counted twice'),
      ]);
      final posted = await services.stockChecks.post(check.id);
      expect(asked.single.people.map((m) => m.name), ['Malik Sahib']);
      expect(posted.approvedByName, 'Malik Sahib');
      final log = await rows(
        'SELECT summary FROM audit_log '
        "WHERE action_code = '$stockCheckPostedAction'",
      );
      expect(log.single['summary'], contains('approved by Malik Sahib'));
      await expectBalanced();
    });
  });

  group('cashier mode', () {
    late String ali;
    late String bilal;

    Future<void> cashierMode() async {
      await services.setPin(owner, '1947');
      ali = await services.addStaff(
        name: 'Ali',
        role: Role.cashier,
        pin: '1111',
      );
      bilal = await services.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2222',
      );
      await services.cashier.setMode(CashierMode(on: true, salesmen: {ali}));
    }

    test('a salesman cannot post a sale; the bill goes to the cashier and '
        'moves nothing', () async {
      await cashierMode();
      await services.lock();
      await services.signIn(ali, '1111');
      expect(await services.cashier.isSalesman(), isTrue);
      await expectLater(
        sell(paid: const Money.rupees(1000)),
        throwsA(isA<PermissionDenied>()),
      );
      final ledger = await rows('SELECT id FROM stock_ledger');
      final journal = await rows('SELECT id FROM journal_entries');

      final held = await services.cashier.hold(
        SaleDraft(lines: [line(oil, 2), line(sugar, 4, rupees: 150)]),
      );
      expect(held.docNo, startsWith('PRO-'));
      expect(await rows('SELECT id FROM stock_ledger'), ledger);
      expect(await rows('SELECT id FROM journal_entries'), journal);
      final queue = await services.cashier.queue();
      expect(queue.single.madeByName, 'Ali');
      expect(queue.single.total, const Money.rupees(2600));
      expect(queue.single.lineCount, 2);
      await expectLater(
        services.cashier.setMode(CashierMode.off),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('a held bill survives a kill and is paid from the cashier\'s queue, '
        'once, naming who made it and who took the money', () async {
      final dir = await Directory.systemTemp.createTemp('cashier_mode');
      final file = File('${dir.path}/books.sqlite');
      final drafts = InMemoryDraftStore();
      Future<AppServices> open() async {
        final s = await AppServices.openWith(
          NativeDatabase(file),
          clock: clock,
          drafts: drafts,
        );
        s.pinHasher = const PinHasher.forTestsOnly();
        return s;
      }

      await services.close();
      services = await open();
      await seed(services);
      await cashierMode();
      await services.lock();
      await services.signIn(ali, '1111');
      final held = await services.cashier.hold(
        SaleDraft(
          lines: [line(oil, 3)],
          partyId: rashid,
          partyName: 'Rashid Traders',
        ),
      );

      // Killed: nothing but the file is left.
      await services.close();
      services = await open();
      await services.signIn(bilal, '2222');
      final queue = await services.cashier.queue();
      expect(queue.single.id, held.id);
      expect(queue.single.partyName, 'Rashid Traders');

      final lines = await services.cashier.linesOf(held.id);
      expect(lines.single.qty, Qty.units(3));
      final bill = await sell(
        party: rashid,
        tins: 3,
        paid: const Money.rupees(3000),
        convertedFromId: held.id,
      );
      expect(await services.cashier.queue(), isEmpty);
      final doc = await rows(
        'SELECT created_by, salesperson_id, balance_paisa FROM documents '
        'WHERE id = ?',
        [bill.documentId],
      );
      expect(doc.single['created_by'], bilal);
      expect(doc.single['salesperson_id'], ali);
      expect(doc.single['balance_paisa'], 0);
      final paper = await services.queries.receiptFor(
        services.identity!.firmId,
        bill.documentId,
      );
      expect(paper!.cashierName, 'Bilal (bill: Ali)');
      expect((await services.cashier.held(held.id))!.paidAs, bill.docNo);

      // Two cashiers cannot both take money for it.
      await expectLater(
        sell(
          party: rashid,
          tins: 3,
          paid: const Money.rupees(3000),
          convertedFromId: held.id,
        ),
        throwsA(isA<HeldBillRefused>()),
      );
      expect(await bills(), 1);
      await expectBalanced();
      await services.close();
      services = await openInMemoryServices(clock: clock);
      await dir.delete(recursive: true);
    });

    test(
      'a held bill set aside needs a reason, and Data Lock\'s PIN',
      () async {
        await cashierMode();
        final held = await services.cashier.hold(
          SaleDraft(lines: [line(oil, 1)]),
        );
        await services.audit.setDataLock(on: true);
        await expectLater(
          services.cashier.drop(held.id, ' '),
          throwsA(isA<HeldBillRefused>()),
        );
        await expectLater(
          services.cashier.drop(held.id, 'Customer walked away'),
          throwsA(isA<ApprovalNeeded>()),
        );
        expect(await services.cashier.queue(), hasLength(1));
        answerWith([ApprovalAnswer(userId: owner, pin: '1947')]);
        await services.cashier.drop(held.id, 'Customer walked away');
        expect(await services.cashier.queue(), isEmpty);
        expect((await services.cashier.held(held.id))!.dropped, isTrue);
        // Set aside, it is no longer standing, and nothing is made of it.
        await expectLater(
          sell(paid: const Money.rupees(1000), convertedFromId: held.id),
          throwsA(anyOf(isA<HeldBillRefused>(), isA<StateError>())),
        );
        expect(await bills(), 0);
      },
    );
  });
}
