import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

void main() {
  group('roles', () {
    test('the owner can do everything', () {
      expect(Role.owner.permissions, Permission.values.toSet());
    });

    test('a cashier sells and takes money, and nothing else', () {
      expect(Role.cashier.can(Permission.sell), isTrue);
      expect(Role.cashier.can(Permission.takePayments), isTrue);
      expect(Role.cashier.can(Permission.voidDocuments), isFalse);
      expect(Role.cashier.can(Permission.seeCosts), isFalse);
      expect(Role.cashier.can(Permission.reports), isFalse);
      expect(Role.cashier.can(Permission.backups), isFalse);
    });

    test('only the owner manages staff, backups and settings', () {
      for (final role in [Role.manager, Role.accountant, Role.cashier]) {
        expect(role.can(Permission.manageUsers), isFalse, reason: role.name);
        expect(role.can(Permission.backups), isFalse, reason: role.name);
        expect(role.can(Permission.settings), isFalse, reason: role.name);
      }
    });

    test('an accountant keeps the books but does not work the counter', () {
      expect(Role.accountant.can(Permission.reports), isTrue);
      expect(Role.accountant.can(Permission.sell), isFalse);
      expect(Role.accountant.can(Permission.voidDocuments), isFalse);
    });

    test('a role nobody knows is not read as any role', () {
      expect(Role.parse('cashier'), Role.cashier);
      expect(Role.parse('admin'), isNull);
    });

    test('a discount a paisa over the limit is over it', () {
      expect(discountShareBp(discountPaisa: 500, grossPaisa: 10000), 500);
      expect(discountShareBp(discountPaisa: 501, grossPaisa: 10000), 501);
      expect(discountShareBp(discountPaisa: 1, grossPaisa: 30000), 1);
      expect(discountShareBp(discountPaisa: 0, grossPaisa: 30000), 0);
    });
  });
}
