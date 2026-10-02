import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The counter's search and the khata's, however the name was spelled (M56).
///
/// The keys themselves are proved in pk_domain. This is the SQL: that a row
/// keyed by the real write path is found by every spelling of it, that what
/// the shopkeeper actually typed still comes first, and that paging through
/// a ranked list neither drops a row nor shows one twice.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late DriftAppQueries queries;
  late String pcs;

  setUp(() async {
    db = await openTestDatabase();
    final clock = FixedClock(DateTime.utc(2026, 10, 2, 9));
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
    catalogue = DriftCatalogueWriter(
      TxRunner(database: db, ids: ids, hlc: hlc),
    );
    queries = DriftAppQueries(db);
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
  });

  tearDown(() async => db.close());

  Future<void> stock(List<String> names, {String? code}) async {
    for (final name in names) {
      await catalogue.addItem(
        actor,
        ItemDraft(
          name: name,
          code: code,
          baseUnitId: pcs,
          saleRate: Rate.rupees(100),
        ),
      );
    }
  }

  Future<List<String>> found(String query, {int limit = 40}) async => [
    for (final item in await queries.searchItems(
      firm.firmId,
      query: query,
      limit: limit,
    ))
      item.name,
  ];

  group('spelling search', () {
    test('aata and atta typed in Urdu find Atta, and what was typed comes '
        'first', () async {
      await stock([
        'Atta Chakki 10kg',
        'Aata Special',
        'آٹا',
        'Anda Desi',
        'Chana Dal',
      ]);

      final atta = await found('atta');
      expect(atta.first, 'Atta Chakki 10kg', reason: 'typed as it is spelled');
      expect(atta, containsAll(['Aata Special', 'آٹا']));
      expect(atta, isNot(contains('Anda Desi')));

      final aata = await found('aata');
      expect(aata.first, 'Aata Special');
      expect(aata, containsAll(['Atta Chakki 10kg', 'آٹا']));

      final urdu = await found('آٹا');
      expect(urdu.first, 'آٹا', reason: 'the item named exactly that');
      expect(urdu, containsAll(['Atta Chakki 10kg', 'Aata Special']));
      expect(urdu, isNot(contains('Chana Dal')));
    });

    test('chini finds Cheeni, and never Chana', () async {
      await stock(['Cheeni Desi', 'Chini 1kg', 'Chana Dal', 'Chawal Basmati']);

      expect(await found('chini'), ['Chini 1kg', 'Cheeni Desi']);
      expect(await found('cheeni'), ['Cheeni Desi', 'Chini 1kg']);
      expect(
        await found('چینی'),
        unorderedEquals(['Cheeni Desi', 'Chini 1kg']),
      );
    });

    test('dots, hyphens and spaces do not matter', () async {
      await stock(['T.V. Stand', '7UP 1.5L', 'Tooth Paste Medicam']);

      expect(await found('tv'), ['T.V. Stand']);
      expect(await found('7 up'), ['7UP 1.5L']);
      expect(await found('7-up'), ['7UP 1.5L']);
      expect(await found('toothpaste'), ['Tooth Paste Medicam']);
      // Words in any order.
      expect(await found('medicam tooth'), ['Tooth Paste Medicam']);
    });

    test('an item named in Urdu is found by its Roman spelling', () async {
      await stock(['چاول', 'دودھ', 'زیرہ', 'چینی']);

      expect(await found('doodh'), ['دودھ']);
      expect(await found('jeera'), ['زیرہ']);
      expect(await found('cheeni'), ['چینی']);
      // Urdu does not write the second a of chawal, so it is the skeleton
      // that finds it.
      expect(await found('chawal'), ['چاول']);
    });

    test('a code or a barcode still finds its item first', () async {
      await stock(['Sufi Banaspati'], code: 'ATT1');
      await stock(['Atta Chakki 10kg']);

      expect((await found('ATT1')).first, 'Sufi Banaspati');
    });

    test(
      'a search of punctuation finds nothing rather than everything',
      () async {
        await stock(['Atta Chakki 10kg', 'Chini 1kg']);
        expect(await found('#!'), isEmpty);
        expect(await found(''), hasLength(2), reason: 'an empty box browses');
      },
    );

    test(
      'paging a ranked search neither drops a row nor repeats one',
      () async {
        // Fifty spelled the way the cashier types and fifty the other way, so
        // the pages have to cross from one rank to the next.
        await stock([
          for (var i = 0; i < 50; i++) 'Cheeni Pack $i',
          for (var i = 0; i < 50; i++) 'Chini Pack $i',
        ]);

        final seen = <String>[];
        String? after;
        for (var page = 0; page < 30; page++) {
          final rows = await queries.searchItems(
            firm.firmId,
            query: 'chini',
            afterId: after,
            limit: 7,
          );
          if (rows.isEmpty) break;
          seen.addAll(rows.map((r) => r.name));
          after = rows.last.id;
        }
        expect(seen, hasLength(100));
        expect(seen.toSet(), hasLength(100), reason: 'a row shown twice');
        expect(
          seen.take(50).every((n) => n.startsWith('Chini')),
          isTrue,
          reason: 'what was typed comes before what only sounds like it',
        );
      },
    );

    test('the khata finds Rahman when Rehman is typed, and by phone', () async {
      for (final (name, phone) in const [
        ('Rehman Traders', '0300 4471203'),
        ('Rahim Sons', null),
        ('محمد علی', null),
      ]) {
        await catalogue.addParty(actor, PartyDraft(name: name, phone: phone));
      }
      Future<List<String>> parties(String q) async => [
        for (final p in await queries.searchParties(firm.firmId, query: q))
          p.name,
      ];

      expect(await parties('rahman'), ['Rehman Traders']);
      expect(await parties('4471203'), ['Rehman Traders']);
      expect(await parties('muhammad'), ['محمد علی']);
      expect(await parties('علی'), ['محمد علی']);
      // An empty box lists the khata alphabetically, Urdu after Roman.
      expect(await parties(''), ['Rahim Sons', 'Rehman Traders', 'محمد علی']);
    });

    test('a name edited is found by its new spelling', () async {
      final id = await catalogue.addItem(
        actor,
        ItemDraft(name: 'Gur Desi', baseUnitId: pcs, saleRate: Rate.rupees(1)),
      );
      await catalogue.updateItem(
        actor,
        id,
        ItemDraft(
          name: 'Shakar Desi',
          baseUnitId: pcs,
          saleRate: Rate.rupees(1),
        ),
      );
      expect(await found('shakkar'), ['Shakar Desi']);
      expect(await found('gur'), isEmpty);
    });
  });
}
