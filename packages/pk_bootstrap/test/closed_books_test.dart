import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Who changed what and when, a day once closed staying closed, and a PIN
/// before anything is undone (M42) — against a real database, through the
/// services every screen uses.
void main() {
  late AppServices services;
  late FixedClock clock;
  late String owner;
  late String oil;
  late String cash;

  setUp(() async {
    // 3 October, a quarter past two in the afternoon in Lahore.
    clock = FixedClock(DateTime.utc(2026, 10, 3, 9, 15));
    services = await openInMemoryServices(
      clock: clock,
      transports: [_Printer()],
    );
    await services.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    owner = services.currentUser!.id;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    oil = await services.catalogue.addItem(
      // On the shelf since the first of last month, so a bill dated back
      // to September sells stock that was already there.
      services.actorNow().at(DateTime.utc(2026, 9, 1, 5)),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(2500),
        openingStock: Qty.units(20),
        openingRate: Rate.rupees(2100),
      ),
    );
    cash = (await services.queries.paymentAccounts(
      firm.id,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
  });

  tearDown(() => services.close());

  /// A cash sale of one tin, as of [on] (Pakistan time, mid-morning), or
  /// now.
  Future<PostedSale> sell({String? on}) {
    var actor = services.actorNow();
    if (on != null) {
      final d = BusinessDate(on);
      actor = actor.at(DateTime.utc(d.year, d.month, d.day, 5));
    }
    return services.postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: const Money.rupees(2500),
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

  Future<void> expectBalanced() async {
    final health = await services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  }

  /// The prompt the app shows, answered as the person at the phone would.
  /// Records each ask.
  List<ApprovalAsk> answerWith(List<ApprovalAnswer?> answers) {
    final asked = <ApprovalAsk>[];
    services.audit.prompt = (ask) async {
      asked.add(ask);
      return asked.length <= answers.length ? answers[asked.length - 1] : null;
    };
    return asked;
  }

  group('closed books', () {
    test('a sale dated inside closed books is refused in words, and nothing is '
        'written', () async {
      await services.audit.closeBooksThrough(BusinessDate('2026-09-30'));
      final before = await rows('SELECT id FROM documents');

      await expectLater(
        sell(on: '2026-09-28'),
        throwsA(
          isA<ApprovalNeeded>()
              .having((e) => e.kind, 'kind', ApprovalKind.closedBooks)
              .having(
                (e) => '$e',
                'words',
                allOf(
                  contains('closed up to 2026-09-30'),
                  contains('dated 2026-09-28'),
                  contains('Only the owner'),
                ),
              ),
        ),
      );
      expect(await rows('SELECT id FROM documents'), before);

      // The day after the closing is open, and so is today.
      await sell(on: '2026-10-01');
      await sell();
      expect(await rows('SELECT id FROM documents'), hasLength(2));
      await expectBalanced();
    });

    test('the owner lets a late bill in with their PIN and a reason, and the '
        'log says who and why', () async {
      await services.setPin(owner, '1947');
      await services.audit.closeBooksThrough(BusinessDate('2026-09-30'));
      final asked = answerWith([
        ApprovalAnswer(userId: owner, pin: '0000', reason: 'Saturday bill'),
        ApprovalAnswer(userId: owner, pin: '1947', reason: 'Saturday bill'),
      ]);

      final bill = await sell(on: '2026-09-27');

      expect(asked, hasLength(2));
      expect(asked.first.needed.kind, ApprovalKind.closedBooks);
      expect(asked.first.needsReason, isTrue);
      expect(asked.first.people.map((m) => m.name), ['Malik Sahib']);
      expect(asked.last.problem, ApprovalProblem.wrongPin);

      final doc = await rows(
        'SELECT doc_date_local, status FROM documents WHERE id = ?',
        [bill.documentId],
      );
      expect(doc.single['doc_date_local'], '2026-09-27');
      expect(doc.single['status'], 'posted');

      final log = await rows(
        'SELECT entity_table, entity_id, summary, after_json FROM audit_log '
        "WHERE action_code = 'CLOSED_BOOKS_OVERRIDDEN'",
      );
      expect(log.single['entity_table'], 'documents');
      expect(log.single['entity_id'], bill.documentId);
      expect(log.single['summary'], contains('Malik Sahib'));
      expect(log.single['summary'], contains('Saturday bill'));
      expect(log.single['after_json'], contains('2026-09-30'));
      await expectBalanced();
    });

    test(
      'a reason is required, and nobody but the owner may give it',
      () async {
        await services.setPin(owner, '1947');
        final nadeem = await services.addStaff(
          name: 'Nadeem',
          role: Role.manager,
          pin: '2468',
        );
        await services.audit.closeBooksThrough(BusinessDate('2026-09-30'));
        await services.lock();
        await services.signIn(nadeem, '2468');

        final asked = answerWith([
          ApprovalAnswer(userId: owner, pin: '1947', reason: '  '),
          ApprovalAnswer(userId: nadeem, pin: '2468', reason: 'Mine'),
        ]);
        await expectLater(
          sell(on: '2026-09-29'),
          throwsA(isA<ApprovalNeeded>()),
        );
        expect(asked.last.problem, ApprovalProblem.reasonNeeded);
        // The manager is not offered: closed books are the owner's to open.
        expect(asked.first.people.map((m) => m.name), ['Malik Sahib']);
        expect(
          await rows(
            "SELECT id FROM documents WHERE doc_date_local = '2026-09-29'",
          ),
          isEmpty,
        );
      },
    );

    test('cancelling a bill dated inside closed books is refused, and a return '
        'today against it goes through', () async {
      final old = await sell(on: '2026-09-25');
      await services.audit.closeBooksThrough(BusinessDate('2026-09-30'));

      await expectLater(
        services.voidDocument(
          services.actorNow(),
          documentId: old.documentId,
          reason: 'Wrong entry',
        ),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => '$e',
            'words',
            contains('Cancelling sale bill ${old.docNo}'),
          ),
        ),
      );
      expect(
        (await rows('SELECT status FROM documents WHERE id = ?', [
          old.documentId,
        ])).single['status'],
        'posted',
      );

      final line =
          (await rows('SELECT id FROM document_lines WHERE document_id = ?', [
                old.documentId,
              ])).single['id']!
              as String;
      final returned = await services.recordReturn(
        services.actorNow(),
        ReturnDraft(
          originalDocumentId: old.documentId,
          lines: [ReturnLineDraft(documentLineId: line, qty: Qty.units(1))],
          reason: 'Seal was broken',
          refundNow: const Money.rupees(2500),
          paymentAccountId: cash,
        ),
      );
      final ret = await rows(
        'SELECT doc_date_local FROM documents WHERE id = ?',
        [returned.documentId],
      );
      expect(ret.single['doc_date_local'], '2026-10-03');
      await expectBalanced();
    });

    test('only the owner closes the books or changes Data Lock', () async {
      await services.setPin(owner, '1947');
      final nadeem = await services.addStaff(
        name: 'Nadeem',
        role: Role.manager,
        pin: '2468',
      );
      await services.lock();
      await services.signIn(nadeem, '2468');

      expect(services.audit.isOwner, isFalse);
      await expectLater(
        services.audit.closeBooksThrough(BusinessDate('2026-09-30')),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        services.audit.setDataLock(on: true),
        throwsA(isA<PermissionDenied>()),
      );
      expect((await services.audit.locks()).closedThrough, isNull);
    });

    test('the day offered is the last day closed at the drawer', () async {
      // No day closed yet: the end of last month.
      expect((await services.audit.suggestedCloseDate()).value, '2026-09-30');
      await services.closeDay(
        services.actorNow(),
        counted: Money.zero,
        note: '',
      );
      expect((await services.audit.suggestedCloseDate()).value, '2026-10-03');
      await expectLater(
        services.audit.closeBooksThrough(BusinessDate('2026-10-04')),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('data lock', () {
    test(
      'with Data Lock on, a cancel asks for a PIN before it is made',
      () async {
        await services.setPin(owner, '1947');
        await services.audit.setDataLock(on: true);
        final bill = await sell();

        // No prompt on screen: refused in words, and the bill stands.
        await expectLater(
          services.voidDocument(
            services.actorNow(),
            documentId: bill.documentId,
            reason: 'Customer changed his mind',
          ),
          throwsA(
            isA<ApprovalNeeded>()
                .having((e) => e.kind, 'kind', ApprovalKind.dataLock)
                .having((e) => '$e', 'words', contains('Data Lock is on')),
          ),
        );
        expect(
          (await rows('SELECT status FROM documents WHERE id = ?', [
            bill.documentId,
          ])).single['status'],
          'posted',
        );

        final asked = answerWith([ApprovalAnswer(userId: owner, pin: '1947')]);
        await services.voidDocument(
          services.actorNow(),
          documentId: bill.documentId,
          reason: 'Customer changed his mind',
        );
        expect(asked.single.needsReason, isFalse);
        expect(
          (await rows('SELECT status FROM documents WHERE id = ?', [
            bill.documentId,
          ])).single['status'],
          'void',
        );
        final pin = await rows(
          "SELECT summary FROM audit_log WHERE action_code = 'DATA_LOCK_PIN_GIVEN'",
        );
        expect(pin.single['summary'], contains('PIN given by Malik Sahib'));
        await expectBalanced();
      },
    );

    test("a manager's own PIN will do, and so will the owner's", () async {
      await services.setPin(owner, '1947');
      final nadeem = await services.addStaff(
        name: 'Nadeem',
        role: Role.manager,
        pin: '2468',
      );
      await services.audit.setDataLock(on: true);
      final first = await sell();
      final second = await sell();
      await services.lock();
      await services.signIn(nadeem, '2468');

      final asked = answerWith([
        ApprovalAnswer(userId: nadeem, pin: '2468'),
        ApprovalAnswer(userId: owner, pin: '1947'),
      ]);
      await services.voidDocument(
        services.actorNow(),
        documentId: first.documentId,
        reason: 'Rung twice',
      );
      await services.voidDocument(
        services.actorNow(),
        documentId: second.documentId,
        reason: 'Rung twice',
      );
      expect(asked.first.people.map((m) => m.name).toSet(), {
        'Malik Sahib',
        'Nadeem',
      });
      final given = await rows(
        "SELECT summary FROM audit_log WHERE action_code = 'DATA_LOCK_PIN_GIVEN' "
        'ORDER BY at_utc, id',
      );
      expect(given.map((r) => r['summary']), [
        contains('PIN given by Nadeem'),
        contains('PIN given by Malik Sahib'),
      ]);
    });

    test('Data Lock needs the owner to have a PIN, and turning it off asks for '
        'that PIN', () async {
      await expectLater(
        services.audit.setDataLock(on: true),
        throwsA(isA<PermissionDenied>()),
      );
      await services.setPin(owner, '1947');
      await services.audit.setDataLock(on: true);

      await expectLater(
        services.audit.setDataLock(on: false),
        throwsA(isA<ApprovalNeeded>()),
      );
      expect((await services.audit.locks()).dataLock, isTrue);

      answerWith([ApprovalAnswer(userId: owner, pin: '1947')]);
      await services.audit.setDataLock(on: false);
      expect((await services.audit.locks()).dataLock, isFalse);
    });

    test(
      'hiding a customer and reopening closed books are guarded too',
      () async {
        await services.setPin(owner, '1947');
        final aslam = await services.catalogue.addParty(
          services.actorNow(),
          const PartyDraft(name: 'Aslam'),
        );
        await services.audit.closeBooksThrough(BusinessDate('2026-09-30'));
        await services.audit.setDataLock(on: true);

        await expectLater(
          services.catalogue.archiveParty(services.actorNow(), aslam),
          throwsA(isA<ApprovalNeeded>()),
        );
        await expectLater(
          services.audit.closeBooksThrough(null),
          throwsA(isA<ApprovalNeeded>()),
        );
        expect(
          (await services.audit.locks()).closedThrough?.value,
          '2026-09-30',
        );
      },
    );
  });

  group('history', () {
    test(
      "a bill's history shows its print, its cancel and the reason, in order",
      () async {
        final bill = await sell();
        clock.advance(const Duration(minutes: 3));
        final printed = await services.printing.print(
          actor: services.actorNow(),
          settings: const PrinterSettings(
            transportKind: 'tcp',
            address: '192.168.1.50:9100',
            name: 'Counter printer',
          ),
          jobKey: printJobKey(
            documentId: bill.documentId,
            revision: 1,
            columns: 48,
          ),
          bytes: const [0x1B, 0x40],
          documentId: bill.documentId,
        );
        expect(printed.outcome, PrintOutcome.printed);
        clock.advance(const Duration(minutes: 10));
        await services.voidDocument(
          services.actorNow(),
          documentId: bill.documentId,
          reason: 'Customer changed his mind',
        );

        final events = await services.audit.history(
          RecordRef.document(bill.documentId),
        );
        expect(events.map((e) => e.actionCode), [
          'SALE_POSTED',
          'PAID_AT_COUNTER',
          'PRINTED',
          'DOCUMENT_VOIDED',
        ]);
        final cancel = events.last;
        expect(cancel.kind, HistoryKind.cancelled);
        expect(cancel.reason, 'Customer changed his mind');
        expect(cancel.who, 'Malik Sahib');
        expect(cancel.device, 'Counter 1');
        expect(events[2].kind, HistoryKind.printed);
        expect(events[2].atUtcMillis, lessThan(cancel.atUtcMillis));
        await expectBalanced();
      },
    );

    test('a customer edited keeps what each field was', () async {
      final aslam = await services.catalogue.addParty(
        services.actorNow(),
        const PartyDraft(name: 'Aslam', phone: '03001234567'),
      );
      clock.advance(const Duration(minutes: 1));
      await services.catalogue.updateParty(
        services.actorNow(),
        aslam,
        const PartyDraft(name: 'Aslam Bhai', phone: '03007654321'),
      );

      final events = await services.audit.history(RecordRef.party(aslam));
      expect(events.map((e) => e.actionCode), [
        'PARTY_CREATED',
        'PARTY_UPDATED',
      ]);
      final changes = {
        for (final c in events.last.changes) c.field: (c.before, c.after),
      };
      expect(changes['phone'], ('03001234567', '03007654321'));
      expect(changes['name'], ('Aslam', 'Aslam Bhai'));
      expect(changes.containsKey('name_search'), isFalse);
    });

    test('an item repriced keeps the old price beside the new', () async {
      final firm = (await services.queries.currentFirm())!;
      final pcs = (await services.queries.units(
        firm.id,
      )).firstWhere((u) => u.code == 'pcs');
      await services.catalogue.updateItem(
        services.actorNow(),
        oil,
        ItemDraft(
          name: 'Cooking Oil 5L',
          baseUnitId: pcs.id,
          saleRate: Rate.rupees(2650),
          barcode: '8964000000017',
        ),
      );
      final edit = (await services.audit.history(
        RecordRef.item(oil),
      )).firstWhere((e) => e.actionCode == 'ITEM_UPDATED');
      final changes = {
        for (final c in edit.changes) c.field: (c.before, c.after),
      };
      expect(changes['sale_rate_milli_paisa'], (
        Rate.rupees(2500).inMilliPaisa,
        Rate.rupees(2650).inMilliPaisa,
      ));
      expect(changes['barcode'], (null, '8964000000017'));
    });

    test(
      'a corrected receipt and its replacement point at each other',
      () async {
        final aslam = await services.catalogue.addParty(
          services.actorNow(),
          const PartyDraft(name: 'Aslam', openingBalance: Money.rupees(5000)),
        );
        final wrong = await services.recordReceipt(
          services.actorNow(),
          ReceiptDraft(
            partyId: aslam,
            amount: const Money.rupees(5000),
            mode: 'cash',
            paymentAccountId: cash,
          ),
        );
        clock.advance(const Duration(minutes: 2));
        final right = await services.corrections.editReceipt(
          services.actorNow(),
          paymentId: wrong.paymentId,
          draft: ReceiptDraft(
            partyId: aslam,
            amount: const Money.rupees(500),
            mode: 'cash',
            paymentAccountId: cash,
          ),
          reason: 'Typed a zero too many',
        );

        final old = await services.audit.history(
          RecordRef.payment(wrong.paymentId),
        );
        final onward = old.firstWhere((e) => e.actionCode == 'PAYMENT_EDITED');
        expect(onward.linked, RecordRef.payment(right.id));
        expect(onward.linkedLabel, right.no);
        expect(onward.reason, 'Typed a zero too many');
        expect(
          onward.changes.single.field,
          'amount_paisa',
          reason: 'Rs 5,000 became Rs 500',
        );
        expect(old.any((e) => e.actionCode == 'PAYMENT_VOIDED'), isTrue);

        final fresh = await services.audit.history(RecordRef.payment(right.id));
        final back = fresh.firstWhere((e) => e.actionCode == 'PAYMENT_EDITED');
        expect(back.linked, RecordRef.payment(wrong.paymentId));
        await expectBalanced();
      },
    );

    test('a cashier may not read a history', () async {
      await services.setPin(owner, '1947');
      final bilal = await services.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      final bill = await sell();
      await services.lock();
      await services.signIn(bilal, '1357');
      expect(
        () => services.audit.history(RecordRef.document(bill.documentId)),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });
}

/// A printer that takes every byte.
final class _Printer implements PrinterTransport {
  @override
  String get kind => 'tcp';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {}
}
