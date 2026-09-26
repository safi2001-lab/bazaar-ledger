import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_platform/pk_platform.dart' show InMemoryDraftStore;

/// Two firms on one phone: the kiryana store and the wholesale agency next
/// door, each with its own books.
void main() {
  late AppServices services;

  setUp(() async {
    services = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 9, 26, 9, 15)),
    );
    await services.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
  });

  tearDown(() => services.close());

  group('firms', () {
    test('a second firm is added and the phone stays on the first', () async {
      final agency = await services.addFirm(
        shopName: 'Chishti Traders',
        ownerName: 'Malik Sahib',
      );
      final firms = await services.queries.firms();
      expect(
        [for (final f in firms) f.name],
        ['Chishti Kiryana Store', 'Chishti Traders'],
      );
      expect(
        (await services.queries.currentFirm())!.name,
        'Chishti Kiryana Store',
      );
      expect(agency, isNot(services.identity!.firmId));
    });

    test('each firm keeps its own khatas', () async {
      await services.catalogue.addParty(
        services.actorNow(),
        const PartyDraft(
          name: 'Store Customer',
          openingBalance: Money.rupees(100),
        ),
      );
      final agency = await services.addFirm(
        shopName: 'Chishti Traders',
        ownerName: 'Malik Sahib',
      );
      await services.switchFirm(agency);

      expect((await services.queries.currentFirm())!.name, 'Chishti Traders');
      expect(services.actorNow().firmId, agency);
      final theirs = await services.queries.searchParties(agency);
      expect(
        theirs,
        isEmpty,
        reason: 'the store customer is not the agency\'s',
      );
      await services.catalogue.addParty(
        services.actorNow(),
        const PartyDraft(name: 'Agency Customer'),
      );

      final store = (await services.queries.firms()).first.id;
      await services.switchFirm(store);
      final mine = await services.queries.searchParties(store);
      expect([for (final p in mine) p.name], ['Store Customer']);
    });

    test('only the owner adds or switches firms', () async {
      await services.setPin(services.currentUser!.id, '1947');
      final bilal = await services.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2468',
      );
      await services.lock();
      await services.signIn(bilal, '2468');
      await expectLater(
        services.addFirm(shopName: 'Mine', ownerName: 'Bilal'),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  test('firms the phone reopens on the firm it last had open', () async {
    final dir = await Directory.systemTemp.createTemp('two_firms');
    final file = File('${dir.path}/books.sqlite');
    final drafts = InMemoryDraftStore();
    final first = await AppServices.openWith(
      NativeDatabase(file),
      drafts: drafts,
    );
    await first.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    final agency = await first.addFirm(
      shopName: 'Chishti Traders',
      ownerName: 'Malik Sahib',
    );
    await first.switchFirm(agency);
    await first.close();

    final again = await AppServices.openWith(
      NativeDatabase(file),
      drafts: drafts,
    );
    expect((await again.queries.currentFirm())!.name, 'Chishti Traders');
    expect(again.actorNow().firmId, agency);
    await again.close();
    await dir.delete(recursive: true);
  });
}
