import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Who is at the phone, and what they are allowed to do there.
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

  Future<String> hireCashier() async {
    await services.setPin(services.currentUser!.id, '1947');
    return services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  }

  group('staff', () {
    test('a shop with no PINs opens straight to the owner', () {
      expect(services.isLocked, isFalse);
      expect(services.currentUser!.role, Role.owner);
      expect(services.can(Permission.manageUsers), isTrue);
    });

    test('staff cannot be added before the owner has a PIN', () async {
      await expectLater(
        services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('a cashier signs in with their own PIN and not a wrong one', () async {
      final bilal = await hireCashier();
      await services.lock();
      expect(services.isLocked, isTrue);
      expect(services.actorNow, throwsA(isA<PermissionDenied>()));

      expect(await services.signIn(bilal, '1947'), isFalse);
      expect(services.isLocked, isTrue);
      expect(await services.signIn(bilal, '2468'), isTrue);
      expect(services.currentUser!.name, 'Bilal');
      expect(services.actorNow().userId, bilal);
    });

    test(
      'a cashier rings bills but cannot cancel one or read the reports',
      () async {
        final bilal = await hireCashier();
        await services.lock();
        await services.signIn(bilal, '2468');

        expect(() => services.postSale, returnsNormally);
        expect(() => services.recordReceipt, returnsNormally);
        expect(() => services.voidDocument, throwsA(isA<PermissionDenied>()));
        expect(() => services.reports, throwsA(isA<PermissionDenied>()));
        expect(() => services.recordPurchase, throwsA(isA<PermissionDenied>()));
        expect(() => services.backups, throwsA(isA<PermissionDenied>()));
        await expectLater(
          services.updateFirm({'name': 'Mine now'}),
          throwsA(isA<PermissionDenied>()),
        );
      },
    );

    test('five wrong PINs block sign-in for a while', () async {
      final bilal = await hireCashier();
      await services.lock();
      for (var i = 0; i < 5; i++) {
        expect(await services.signIn(bilal, '0000'), isFalse);
      }
      await expectLater(
        services.signIn(bilal, '2468'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('staff who have left cannot sign in', () async {
      final bilal = await hireCashier();
      await services.setStaffActive(bilal, active: false);
      await services.lock();
      expect(await services.signIn(bilal, '2468'), isFalse);
    });

    test('the sale a cashier rings is theirs in the books', () async {
      final bilal = await hireCashier();
      await services.lock();
      await services.signIn(bilal, '2468');

      final firm = (await services.queries.currentFirm())!;
      final units = await services.queries.units(firm.id);
      final cash = (await services.queries.paymentAccounts(
        firm.id,
      )).firstWhere((a) => a.modeLabel == 'cash');
      final posted = await services.postSale(
        services.actorNow(),
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: await _anItem(services, units.first.id),
              itemName: 'Sugar 1kg',
              qty: Qty.units(1),
              baseQty: Qty.units(1),
              unitCode: 'pcs',
              rate: Rate.rupees(160),
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash.id,
              mode: 'cash',
              amount: const Money.rupees(160),
            ),
          ],
        ),
      );
      final row = await services.database
          .customSelect(
            'SELECT created_by FROM documents WHERE id = ?',
            variables: [Variable<String>(posted.documentId)],
          )
          .getSingle();
      expect(row.read<String>('created_by'), bilal);
    });
  });
}

Future<String> _anItem(AppServices services, String unitId) async {
  // Added by the owner before the counter opens.
  return services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: 'Sugar 1kg',
      baseUnitId: unitId,
      saleRate: Rate.rupees(160),
    ),
  );
}
