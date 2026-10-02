import 'dart:convert';

import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Customers in groups, and the note the counter sees (M40), against a real
/// database.
///
/// The widget tests drive the screens. These prove what the screens stand
/// on: that a group is one group however it was typed, that renaming one
/// moves every member in a single transaction with each move in the outbox
/// for the other counters, that a rename which cannot finish moves nobody,
/// and that the totals a group shows and the reports will read are the
/// khata's own figures.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase sell;
  late RecordPurchaseUseCase buy;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    catalogue = DriftCatalogueWriter(runner);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    riceId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Chawal Basmati',
        baseUnitId: pcsUnitId,
        saleRate: Rate.rupees(100),
        openingStock: Qty.units(500),
        openingRate: Rate.rupees(60),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<String> party(
    String name, {
    String? group,
    int owed = 0,
    String type = 'customer',
    String? remarks,
  }) => catalogue.addParty(
    actor,
    PartyDraft(
      name: name,
      partyType: type,
      group: group,
      remarks: remarks,
      openingBalance: Money.rupees(owed),
    ),
  );

  /// A bill of Rs [rupees] to [partyId] on [day], all of it on udhaar.
  Future<void> billOn(String partyId, int rupees, {DateTime? day}) => sell(
    day == null ? actor : firm.actorAt(day),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(rupees ~/ 100),
          baseQty: Qty.units(rupees ~/ 100),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(100),
        ),
      ],
      tenders: const [],
    ),
  );

  Future<void> deliveryFrom(String partyId, int rupees) => buy(
    actor,
    PurchaseDraft(
      partyId: partyId,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 10),
        ),
      ],
    ),
  );

  Future<String?> groupOf(String partyId) async =>
      (await db
              .customSelect(
                'SELECT party_group FROM parties WHERE id = ?',
                variables: [Variable<String>(partyId)],
              )
              .getSingle())
          .readNullable<String>('party_group');

  Future<int> lastSeq() async =>
      (await db
              .customSelect('SELECT COALESCE(MAX(seq), 0) AS s FROM change_log')
              .getSingle())
          .read<int>('s');

  group('a group', () {
    test('typed in another case joins the one the shop already has', () async {
      final a = await party('Bilal General Store', group: 'Route 3');
      final b = await party('Ali Kiryana', group: '  route   3 ');
      final c = await party('Canal View Hotel', group: 'Hotels');
      final d = await party('Walk-in regular', group: '   ');

      expect(await groupOf(a), 'Route 3');
      expect(
        await groupOf(b),
        'Route 3',
        reason:
            'a second route with one customer on it would be missing '
            'from every list filtered by the real one',
      );
      expect(await groupOf(c), 'Hotels');
      expect(await groupOf(d), isNull, reason: 'blank is no group');

      final groups = await queries.partyGroups(firm.firmId);
      expect(groups.map((g) => (g.name, g.members)), [
        ('Hotels', 1),
        ('Route 3', 2),
      ]);
    });

    test('carries what its members owe, and what the shop owes them', () async {
      final bilal = await party('Bilal', group: 'Route 3', owed: 5000);
      final ali = await party('Ali', group: 'Route 3');
      await billOn(ali, 2500);
      // Paid ahead: the shop is holding Rs 700 of theirs.
      await party('Hamid', group: 'Route 3', owed: -700);
      await party('Not on the route', owed: 99000);
      final mill = await party(
        'Punjab Rice Mills',
        group: 'Route 3',
        type: 'supplier',
      );
      await deliveryFrom(mill, 9000);

      final route = (await queries.partyGroups(
        firm.firmId,
      )).singleWhere((g) => g.name == 'Route 3');
      expect(route.members, 4);
      expect(route.receivable, const Money.rupees(7500));
      expect(
        route.payable,
        const Money.rupees(9700),
        reason:
            'the mill delivery and the advance held are both money the '
            'shop owes this route',
      );

      // And the list narrowed to it shows exactly its members.
      final members = await queries.partyList(
        firm.firmId,
        filter: const PartyListFilter(group: 'Route 3'),
      );
      expect(members.map((p) => p.name), [
        'Ali',
        'Bilal',
        'Hamid',
        'Punjab Rice Mills',
      ]);
      expect(members.every((p) => p.group == 'Route 3'), isTrue);
      expect((await queries.partyById(firm.firmId, bilal))!.group, 'Route 3');
    });
  });

  group('the khata list', () {
    test('sorts by balance and by the oldest debt', () async {
      final march = await party('March Udhaar');
      final august = await party('August Udhaar');
      final big = await party('Big Recent');
      final settled = await party('Aamir Settled');
      await billOn(march, 3000, day: DateTime.utc(2026, 3, 10, 9));
      await billOn(august, 1000, day: DateTime.utc(2026, 8, 1, 9));
      await billOn(big, 40000);

      final byBalance = await queries.partyList(
        firm.firmId,
        filter: const PartyListFilter(sort: PartySort.balance),
      );
      expect(byBalance.map((p) => p.name), [
        'Big Recent',
        'March Udhaar',
        'August Udhaar',
        'Aamir Settled',
      ]);

      final byAge = await queries.partyList(
        firm.firmId,
        filter: const PartyListFilter(sort: PartySort.oldestDue),
      );
      expect(
        byAge.map((p) => p.name),
        ['March Udhaar', 'August Udhaar', 'Big Recent', 'Aamir Settled'],
        reason:
            'Rs 3,000 owed since March is chased before Rs 40,000 owed '
            'since this morning, and somebody who owes nothing is last',
      );
      expect(settled, isNotEmpty);
    });

    test('narrows to the people in no group', () async {
      await party('In a route', group: 'Route 3');
      await party('Nowhere');
      final loose = await queries.partyList(
        firm.firmId,
        filter: const PartyListFilter(ungrouped: true),
      );
      expect(loose.map((p) => p.name), ['Nowhere']);
    });
  });

  group('renaming a group', () {
    test(
      'moves every member in one transaction, each through the outbox',
      () async {
        final ids = [
          await party('Bilal', group: 'Route 3'),
          await party('Ali', group: 'Route 3'),
          await party('Hamid', group: 'Route 3'),
        ];
        // Hidden for the season, and still on the route.
        await catalogue.archiveParty(actor, ids.last);
        final hotel = await party('Canal View Hotel', group: 'Hotels');
        final before = await lastSeq();

        final moved = await catalogue.renamePartyGroup(
          actor,
          from: 'Route 3',
          to: 'Route 3 Gulberg',
        );

        expect(moved, 3);
        for (final id in ids) {
          expect(await groupOf(id), 'Route 3 Gulberg');
        }
        expect(await groupOf(hotel), 'Hotels');

        // Every move is its own outbox entry, so a counter on the shop's
        // Wi-Fi receives all three; and all three carry one instant, from
        // the one transaction that made them.
        final changes = await db
            .customSelect(
              'SELECT entity_id, op, payload_json, at_utc FROM change_log '
              "WHERE seq > ? AND entity_table = 'parties' ORDER BY seq",
              variables: [Variable<int>(before)],
            )
            .get();
        expect(changes.map((c) => c.read<String>('entity_id')).toSet(), {
          ...ids,
        });
        expect(changes.map((c) => c.read<String>('op')).toSet(), {'update'});
        for (final c in changes) {
          final payload =
              jsonDecode(c.read<String>('payload_json'))
                  as Map<String, Object?>;
          expect(payload['party_group'], 'Route 3 Gulberg');
        }
        expect(changes.map((c) => c.read<int>('at_utc')).toSet(), hasLength(1));

        final audit = await db
            .customSelect(
              'SELECT summary FROM audit_log '
              "WHERE action_code = 'PARTY_GROUP_RENAMED'",
            )
            .get();
        expect(audit.single.read<String>('summary'), contains('3 moved'));
      },
    );

    test('into a group the shop already has merges the two', () async {
      final a = await party('Bilal', group: 'Rt 3');
      final b = await party('Ali', group: 'Rt 3');
      final c = await party('Hamid', group: 'Route 3');

      final moved = await catalogue.renamePartyGroup(
        actor,
        from: 'Rt 3',
        to: 'route 3',
      );

      expect(moved, 2);
      for (final id in [a, b, c]) {
        expect(await groupOf(id), 'Route 3', reason: "the shop's spelling");
      }
      final groups = await queries.partyGroups(firm.firmId);
      expect(groups.map((g) => (g.name, g.members)), [('Route 3', 3)]);
      expect(
        await db
            .customSelect(
              "SELECT 1 FROM audit_log WHERE action_code = 'PARTY_GROUPS_MERGED'",
            )
            .get(),
        hasLength(1),
      );
    });

    test('that cannot finish moves nobody', () async {
      final ids = [
        await party('Bilal', group: 'Route 3'),
        await party('Ali', group: 'Route 3'),
        await party('Hamid', group: 'Route 3'),
      ];
      // The last member's row refuses to change: a full disk, a dying
      // phone, whatever stops a write half-way down a route.
      await db.customStatement(
        'CREATE TEMP TRIGGER refuse_last BEFORE UPDATE OF party_group '
        "ON parties WHEN NEW.id = '${ids.last}' "
        "BEGIN SELECT RAISE(ABORT, 'the disk is full'); END",
      );
      final before = await lastSeq();

      await expectLater(
        catalogue.renamePartyGroup(actor, from: 'Route 3', to: 'Route 4'),
        throwsA(anything),
      );

      for (final id in ids) {
        expect(
          await groupOf(id),
          'Route 3',
          reason:
              'half a route under one name and half under the other is '
              'the one outcome a rename must never leave behind',
        );
      }
      expect(await lastSeq(), before, reason: 'nothing reached the outbox');
    });

    test('refuses a blank name, and a group nobody is in', () async {
      await party('Bilal', group: 'Route 3');
      expect(
        () => catalogue.renamePartyGroup(actor, from: 'Route 3', to: '  '),
        throwsArgumentError,
      );
      await expectLater(
        catalogue.renamePartyGroup(actor, from: 'Route 9', to: 'Route 10'),
        throwsStateError,
      );
      expect(
        await groupOf((await queries.partyList(firm.firmId)).single.id),
        'Route 3',
      );
    });
  });

  group('setting a group on several', () {
    test('moves those not already there, and can take them out', () async {
      final a = await party('Bilal');
      final b = await party('Ali', group: 'Hotels');
      final c = await party('Hamid', group: 'Hotels');
      final before = await lastSeq();

      final moved = await catalogue.setPartyGroup(actor, [a, b, c], 'hotels');
      expect(moved, 1, reason: 'two were already in Hotels');
      for (final id in [a, b, c]) {
        expect(await groupOf(id), 'Hotels');
      }
      expect(await lastSeq(), greaterThan(before));

      expect(await catalogue.setPartyGroup(actor, [a, b], null), 2);
      expect(await groupOf(a), isNull);
      expect(await groupOf(b), isNull);
      expect(await groupOf(c), 'Hotels');
    });
  });

  group('a note for the counter', () {
    test('is kept with the party, edited, and cleared', () async {
      final id = await party(
        'Rashid Traders',
        remarks: 'Sirf cash — cheque bounce ho chuka',
      );
      expect(
        (await queries.partyById(firm.firmId, id))!.remarks,
        'Sirf cash — cheque bounce ho chuka',
      );
      final draft = (await queries.partyDraft(firm.firmId, id))!;
      expect(draft.remarks, 'Sirf cash — cheque bounce ho chuka');

      // An edit that does not touch it keeps it: the editor writes back
      // what it read.
      await catalogue.updateParty(
        actor,
        id,
        PartyDraft(
          name: draft.name,
          phone: '0300 4471203',
          remarks: draft.remarks,
          group: draft.group,
        ),
      );
      expect(
        (await queries.partyById(firm.firmId, id))!.remarks,
        'Sirf cash — cheque bounce ho chuka',
      );

      await catalogue.updateParty(
        actor,
        id,
        const PartyDraft(name: 'Rashid Traders', remarks: 'Delivery after 5pm'),
      );
      expect(
        (await queries.partyById(firm.firmId, id))!.remarks,
        'Delivery after 5pm',
      );

      await catalogue.updateParty(
        actor,
        id,
        const PartyDraft(name: 'Rashid Traders', remarks: '  '),
      );
      expect((await queries.partyById(firm.firmId, id))!.remarks, isNull);

      // One row, under the id every counter derives for this party, so two
      // counters writing a first note while apart write the same row.
      final rows = await db
          .customSelect(
            'SELECT id, setting_key FROM settings '
            "WHERE setting_key LIKE 'party.remarks.%'",
          )
          .get();
      expect(rows.single.read<String>('id'), 'remarks-$id');
      expect(rows.single.read<String>('setting_key'), 'party.remarks.$id');

      // Written again after being cleared, into the same row.
      await catalogue.updateParty(
        actor,
        id,
        const PartyDraft(name: 'Rashid Traders', remarks: 'Sirf cash'),
      );
      expect((await queries.partyById(firm.firmId, id))!.remarks, 'Sirf cash');
    });

    test('nobody without one has one', () async {
      final id = await party('Bilal General Store');
      expect((await queries.partyById(firm.firmId, id))!.remarks, isNull);
      expect(
        await db
            .customSelect(
              'SELECT 1 FROM settings '
              "WHERE setting_key LIKE 'party.remarks.%'",
            )
            .get(),
        isEmpty,
      );
    });
  });

  group('group totals for the reports', () {
    test('sale, purchase, receivable and payable for a period', () async {
      final bilal = await party('Bilal', group: 'Route 3');
      final ali = await party('Ali', group: 'Route 3');
      final hotel = await party('Canal View Hotel', group: 'Hotels');
      final walkIn = await party('No group regular');
      final mill = await party(
        'Punjab Rice Mills',
        group: 'Mills',
        type: 'supplier',
      );
      await party('Quiet route member', group: 'Route 9');

      // Before the period: counted in what they owe, not in its sales.
      await billOn(bilal, 1000, day: DateTime.utc(2026, 7, 20, 9));
      await billOn(bilal, 2000);
      await billOn(ali, 3000);
      await billOn(hotel, 5000);
      await billOn(walkIn, 700);
      await deliveryFrom(mill, 9000);

      final totals = await queries.partyGroupTotals(
        firm.firmId,
        from: const BusinessDate('2026-08-01'),
        to: const BusinessDate('2026-08-31'),
      );
      final byGroup = {for (final t in totals) t.group: t};

      expect(byGroup.keys, ['Hotels', 'Mills', 'Route 3', 'Route 9', null]);
      expect(byGroup['Route 3']!.sales, const Money.rupees(5000));
      expect(byGroup['Route 3']!.receivable, const Money.rupees(6000));
      expect(byGroup['Route 3']!.parties, 2);
      expect(byGroup['Hotels']!.sales, const Money.rupees(5000));
      expect(byGroup['Mills']!.purchases, const Money.rupees(9000));
      expect(byGroup['Mills']!.payable, const Money.rupees(9000));
      expect(byGroup['Mills']!.sales, Money.zero);
      expect(
        byGroup['Route 9']!.sales,
        Money.zero,
        reason: 'a route that bought nothing is seen to have bought nothing',
      );
      expect(byGroup[null]!.sales, const Money.rupees(700));

      // The rows add up to the shop's own sales for the period.
      final shop = await db
          .customSelect(
            'SELECT SUM(total_paisa) AS s FROM documents '
            "WHERE doc_type = 'sale_invoice' AND status = 'posted' "
            "AND doc_date_local BETWEEN '2026-08-01' AND '2026-08-31'",
          )
          .getSingle();
      expect(
        Money.sum(totals.map((t) => t.sales)),
        Money.paisa(shop.read<int>('s')),
      );
    });
  });
}
