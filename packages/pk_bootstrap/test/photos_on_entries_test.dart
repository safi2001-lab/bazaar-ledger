import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/paper.dart';

/// A photograph of the paper behind an entry (M60) — the supplier's bill on
/// a delivery, the bijli bill on an expense, the deposit slip on a payment —
/// against a real database, through the services every screen uses.
void main() {
  late AppServices shop;
  late FixedClock clock;
  late String firmId;
  late String owner;
  late String cash;
  late String oil;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 10, 3, 9, 15));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    owner = shop.currentUser!.id;
    firmId = (await shop.queries.currentFirm())!.id;
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(2500),
        openingStock: Qty.units(20),
        openingRate: Rate.rupees(2100),
      ),
    );
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
  });

  tearDown(() => shop.close());

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<String> args = const [],
  ]) async => [
    for (final r
        in await shop.database
            .customSelect(
              sql,
              variables: [for (final a in args) Variable<String>(a)],
            )
            .get())
      r.data,
  ];

  Future<RecordedExpense> bijli({int rupees = 4000}) => shop.recordExpense(
    shop.actorNow(),
    ExpenseDraft(
      accountSystemKey: 'utilities',
      amount: Money.rupees(rupees),
      note: 'Bijli ka bill, September',
      paymentAccountId: cash,
    ),
  );

  /// A cash sale of one tin of oil.
  Future<PostedSale> sell() => shop.postSale(
    shop.actorNow(),
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

  Future<String> photograph(
    String table,
    String id, {
    int shade = 1,
    EntryPhotoKind kind = EntryPhotoKind.receipt,
  }) => shop.photos.add(
    ownerTable: table,
    ownerId: id,
    kind: kind,
    source: paper(shade),
    fileName: 'parchi-$shade.bmp',
  );

  group('photos on entries', () {
    test('the bijli bill photographed onto an expense stays on it, small, '
        'saying who put it there', () async {
      final expense = await bijli();
      await photograph('documents', expense.documentId);

      final photos = await shop.photos.of('documents', expense.documentId);
      expect(photos, hasLength(1));
      final photo = photos.single;
      expect(photo.kind, 'receipt_photo');
      expect(photo.addedBy, 'Malik Sahib');
      expect(photo.fromEarlierEntry, isFalse);
      expect(photo.bytes.take(2), [0xFF, 0xD8], reason: 'kept as JPEG');
      expect(photo.bytes.length, lessThanOrEqualTo(EntryPhoto.maxBytes));

      final added = await rows(
        "SELECT summary FROM audit_log WHERE action_code = 'ATTACHMENT_ADDED'",
      );
      expect(added.single['summary'], contains(expense.docNo));
    });

    test('a delivery, a payment, a cheque, a sale bill, a charge and a '
        'khata each keep their own', () async {
      final mill = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
      );
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(
          name: 'Rashid Traders',
          openingBalance: Money.rupees(9000),
        ),
      );
      final pcs = (await shop.queries.units(
        firmId,
      )).firstWhere((u) => u.code == 'pcs');
      final delivery = await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          lines: [
            PurchaseLineDraft(
              itemId: oil,
              itemName: 'Cooking Oil 5L',
              qty: Qty.units(10),
              baseQty: Qty.units(10),
              unitId: pcs.id,
              unitCode: 'pcs',
              rate: Rate.rupees(2100),
            ),
          ],
        ),
      );
      final slip = await shop.recordReceipt(
        shop.actorNow(),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(3000),
          mode: 'cash',
          paymentAccountId: cash,
        ),
      );
      final bill = await sell();
      final charge = await shop.chargeParty(
        shop.actorNow(),
        DebitNoteDraft(
          partyId: rashid,
          partyName: 'Rashid Traders',
          amount: const Money.rupees(500),
          note: 'Bounced cheque ka bank charge',
        ),
      );

      await photograph('documents', delivery.documentId, shade: 2);
      await photograph('payments', slip.paymentId, shade: 3);
      await photograph(
        'payments',
        slip.paymentId,
        shade: 4,
        kind: EntryPhotoKind.cheque,
      );
      await photograph('documents', bill.documentId, shade: 5);
      await photograph('documents', charge.id, shade: 6);
      await photograph(
        'parties',
        rashid,
        shade: 7,
        kind: EntryPhotoKind.papers,
      );

      Future<List<String>> kinds(String table, String id) async => [
        for (final p in await shop.photos.of(table, id)) p.kind,
      ];
      expect(await kinds('documents', delivery.documentId), ['receipt_photo']);
      expect(await kinds('payments', slip.paymentId), [
        'receipt_photo',
        'cheque_image',
      ]);
      expect(await kinds('documents', bill.documentId), ['receipt_photo']);
      expect(await kinds('documents', charge.id), ['receipt_photo']);
      expect(await kinds('parties', rashid), ['other']);
      expect(
        await kinds('parties', mill),
        isEmpty,
        reason: "one khata's papers are not another's",
      );
    });

    test(
      'an entry keeps eight photographs and refuses a ninth in words',
      () async {
        final expense = await bijli();
        for (var i = 1; i <= EntryPhoto.maxPerEntry; i++) {
          await photograph('documents', expense.documentId, shade: i);
        }
        await expectLater(
          photograph('documents', expense.documentId, shade: 99),
          throwsA(
            isA<PhotoRefused>().having(
              (e) => e.reason,
              'reason',
              contains('already has 8 photographs'),
            ),
          ),
        );
        expect(
          await shop.photos.of('documents', expense.documentId),
          hasLength(EntryPhoto.maxPerEntry),
        );
      },
    );

    test('a corrected expense still shows the bill photographed onto the one '
        'it replaced', () async {
      final wrong = await bijli(rupees: 40000);
      await photograph('documents', wrong.documentId);
      clock.advance(const Duration(minutes: 2));

      final right = await shop.corrections.editExpense(
        shop.actorNow(),
        documentId: wrong.documentId,
        draft: ExpenseDraft(
          accountSystemKey: 'utilities',
          amount: const Money.rupees(4000),
          note: 'Bijli ka bill, September',
          paymentAccountId: cash,
        ),
        reason: 'Typed a zero too many',
      );

      final carried = await shop.photos.of('documents', right.id);
      expect(carried, hasLength(1));
      expect(carried.single.fromEarlierEntry, isTrue);
      expect(carried.single.ownerId, wrong.documentId);
      // And it is still on the entry it was put on.
      final kept = await shop.photos.of('documents', wrong.documentId);
      expect(kept.single.fromEarlierEntry, isFalse);
    });

    test('a photograph taken off waits in the bin, says who took it off, and '
        'comes back', () async {
      final expense = await bijli();
      final id = await photograph('documents', expense.documentId);

      await shop.photos.remove(id);
      expect(await shop.photos.of('documents', expense.documentId), isEmpty);
      final binned = await shop.photos.removed();
      expect(binned, hasLength(1));
      expect(binned.single.ownerLabel, expense.docNo);
      expect(binned.single.removedBy, 'Malik Sahib');
      expect(
        (await shop.recycle.marks())['attachments/$id']?.by,
        'Malik Sahib',
      );

      await shop.photos.restore(binned.single);
      final back = await shop.photos.of('documents', expense.documentId);
      expect(back, hasLength(1));
      expect(back.single.bytes, binned.single.bytes, reason: 'the same photo');
      expect(await shop.photos.removed(), isEmpty);
      expect(
        await rows(
          'SELECT summary FROM audit_log WHERE action_code IN '
          "('ATTACHMENT_REMOVED', 'ATTACHMENT_RESTORED') ORDER BY action_code",
        ),
        [
          {'summary': 'Photo taken off entry ${expense.docNo}'},
          {'summary': 'Photo back on entry ${expense.docNo}'},
        ],
      );
    });

    test('a cashier may photograph a bill, but not take a photograph off nor '
        'see a CNIC copy', () async {
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      await photograph('parties', rashid, kind: EntryPhotoKind.papers);
      await shop.setPin(owner, '1947');
      final bilal = await shop.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      final bill = await sell();
      await shop.lock();
      await shop.signIn(bilal, '1357');

      final id = await photograph('documents', bill.documentId);
      expect(await shop.photos.of('documents', bill.documentId), hasLength(1));
      expect(shop.photos.mayRemove, isFalse);
      await expectLater(
        shop.photos.remove(id),
        throwsA(isA<PermissionDenied>()),
      );
      expect(shop.photos.mayHandle('parties'), isFalse);
      expect(await shop.photos.of('parties', rashid), isEmpty);
      await expectLater(
        photograph('parties', rashid, kind: EntryPhotoKind.papers),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('with Data Lock on, taking a photograph off asks for a PIN', () async {
      final expense = await bijli();
      final id = await photograph('documents', expense.documentId);
      await shop.setPin(owner, '1947');
      await shop.audit.setDataLock(on: true);

      await expectLater(
        shop.photos.remove(id),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => e.kind,
            'kind',
            ApprovalKind.dataLock,
          ),
        ),
      );
      expect(
        await shop.photos.of('documents', expense.documentId),
        hasLength(1),
      );

      shop.audit.prompt = (ask) async =>
          ApprovalAnswer(userId: owner, pin: '1947');
      await shop.photos.remove(id);
      expect(await shop.photos.of('documents', expense.documentId), isEmpty);
      final pin = await rows(
        "SELECT summary FROM audit_log WHERE action_code = 'DATA_LOCK_PIN_GIVEN'",
      );
      expect(pin.single['summary'], contains('Photo taken off'));
    });

    test('a photograph is not kept a second time in the outbox', () async {
      // jsonEncode writes bytes as a list of numbers: a 190 KB parchi was
      // 900 KB more of every backup, in a row no other phone could take in.
      final expense = await bijli();
      await photograph('documents', expense.documentId);

      final out = await rows(
        "SELECT payload_json FROM change_log WHERE entity_table = 'attachments'",
      );
      final payload =
          jsonDecode(out.single['payload_json']! as String)
              as Map<String, Object?>;
      expect(payload.containsKey('bytes'), isFalse);
      expect(payload['owner_id'], expense.documentId);
      expect(payload['sha256'], isA<String>());
    });
  });

  group('photos and the shop wi-fi', () {
    test('a picture never stops a counter syncing, and stays on the phone it '
        'was taken on', () async {
      final ticking = _Ticking();
      final master = await openInMemoryServices(clock: ticking);
      final counter = await openInMemoryServices(clock: ticking);
      addTearDown(() async {
        await counter.close();
        await master.close();
      });
      await master.setUpShop(
        shopName: 'Chishti Kiryana Store',
        ownerName: 'Malik Sahib',
        deviceLabel: 'Master',
      );
      final port = await master.sync.startHosting(
        port: 0,
        address: InternetAddress.loopbackIPv4,
      );
      await counter.sync.join(
        host: '127.0.0.1',
        port: port,
        code: master.sync.openJoining(),
        label: 'Counter 2',
      );

      // A parchi on an expense on the master, and an item's own photograph:
      // until M60 the first picture in the books stopped every sync after.
      final masterFirm = (await master.queries.currentFirm())!.id;
      final till = (await master.queries.paymentAccounts(
        masterFirm,
      )).firstWhere((a) => a.modeLabel == 'cash').id;
      final expense = await master.recordExpense(
        master.actorNow(),
        ExpenseDraft(
          accountSystemKey: 'utilities',
          amount: const Money.rupees(4000),
          note: 'Bijli ka bill, September',
          paymentAccountId: till,
        ),
      );
      await master.photos.add(
        ownerTable: 'documents',
        ownerId: expense.documentId,
        kind: EntryPhotoKind.receipt,
        source: paper(1),
        fileName: 'bijli.bmp',
      );
      final units = await master.queries.units(masterFirm);
      final sugar = await master.catalogue.addItem(
        master.actorNow(),
        ItemDraft(
          name: 'Sugar 1kg',
          baseUnitId: units.first.id,
          saleRate: Rate.rupees(160),
        ),
      );
      await master.pictures.setItemPicture(
        master.actorNow(),
        itemId: sugar,
        source: paper(2),
        fileName: 'sugar.bmp',
      );

      await counter.sync.syncNow();

      // Everything else arrived: the expense and the item.
      final arrived = await counter.database
          .customSelect(
            'SELECT COUNT(*) AS n FROM documents WHERE id = ?',
            variables: [Variable<String>(expense.documentId)],
          )
          .getSingle();
      expect(arrived.read<int>('n'), 1);
      expect(
        (await counter.queries.searchItems(
          masterFirm,
          query: 'Sugar',
        )).single.name,
        'Sugar 1kg',
      );
      // The pictures stayed where they were taken.
      expect(await counter.photos.of('documents', expense.documentId), isEmpty);
      expect(await counter.pictures.itemPicture(masterFirm, sugar), isNull);
      expect(
        await master.photos.of('documents', expense.documentId),
        hasLength(1),
      );

      // And the next sync is not stuck behind them.
      final again = await counter.sync.syncNow();
      expect(again.conflicts, 0);
    });
  });
}

/// One clock for two phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 10, 3, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}
