/// Who may do what in the shop.
///
/// A shop with a counter boy and a munshi does not want either of them
/// cancelling bills after the customer has left, reading what the goods
/// cost, or restoring last month's backup over today's books. The owner
/// hands each of them a role, and the role decides.
///
/// Checked where the work is done, at the service boundary every screen
/// goes through, not only by hiding a button: a hidden button is one deep
/// link or one forgotten screen away from being pressed.
library;

import 'package:pk_money/pk_money.dart';

/// The things a role can be allowed to do.
enum Permission {
  /// Ring up a bill at the counter.
  sell,

  /// Take money against a khata.
  takePayments,

  /// Cancel a bill, or a challan whose goods came back.
  voidDocuments,

  /// Take goods back from a customer.
  takeReturns,

  /// Record deliveries from suppliers, returns to them, and pay them.
  purchases,

  /// Record rent, bijli, wages.
  expenses,

  /// Move cheques through the bank: deposit, clear, bounce.
  cheques,

  /// Read the report pack.
  reports,

  /// See what the goods cost and the margin on them.
  seeCosts,

  /// Count the drawer and close the day.
  closeDay,

  /// Read the activity log.
  audit,

  /// Write journal vouchers by hand.
  journal,

  /// Add staff, change their roles and PINs.
  manageUsers,

  /// Seal the books into a backup, or restore one over them.
  backups,

  /// Change the shop's details and preferences.
  settings,
}

/// Why something was refused, in words the person at the counter can act on.
final class PermissionDenied implements Exception {
  const PermissionDenied(this.permission, this.reason);

  final Permission permission;
  final String reason;

  @override
  String toString() => reason;
}

/// A role in the shop.
enum Role {
  /// Everything. The one who set the shop up.
  owner(maxDiscountBp: 10000),

  /// Runs the shop day to day: everything but staff, backups and settings.
  manager(maxDiscountBp: 2000),

  /// Keeps the books: payments, purchases, expenses, cheques and reports,
  /// but not the counter's cancellations.
  accountant(maxDiscountBp: 0),

  /// The counter: bills, payments against a khata, and the day's cash.
  cashier(maxDiscountBp: 500);

  const Role({required this.maxDiscountBp});

  /// The largest discount this role gives on its own, in basis points.
  final int maxDiscountBp;

  /// The role stored as [code], or null when it is not one this app knows.
  static Role? parse(String code) {
    for (final r in values) {
      if (r.name == code) return r;
    }
    return null;
  }

  Set<Permission> get permissions => switch (this) {
    owner => Permission.values.toSet(),
    manager => {
      Permission.sell,
      Permission.takePayments,
      Permission.voidDocuments,
      Permission.takeReturns,
      Permission.purchases,
      Permission.expenses,
      Permission.cheques,
      Permission.reports,
      Permission.seeCosts,
      Permission.closeDay,
      Permission.audit,
    },
    accountant => {
      Permission.journal,
      Permission.takePayments,
      Permission.purchases,
      Permission.expenses,
      Permission.cheques,
      Permission.reports,
      Permission.seeCosts,
      Permission.closeDay,
      Permission.audit,
    },
    cashier => {Permission.sell, Permission.takePayments, Permission.closeDay},
  };

  bool can(Permission permission) => permissions.contains(permission);
}

/// A discount on a bill, as a share of its gross in basis points, rounded up
/// so a discount a paisa over the limit is over it.
int discountShareBp({required int discountPaisa, required int grossPaisa}) {
  if (grossPaisa <= 0 || discountPaisa <= 0) return 0;
  return (discountPaisa * 10000 + grossPaisa - 1) ~/ grossPaisa;
}

/// Whether [role] may give [discount] off a bill whose goods come to
/// [subtotal], on its own say-so.
///
/// The ceiling is the role's, or the party's standing discount when that is
/// higher: the owner set it on the khata, so a cashier ringing that customer
/// is applying the owner's decision, not making one. Exactly at the ceiling
/// is allowed.
bool discountAllowed({
  required Role role,
  required Money subtotal,
  required Money discount,
  int standingBp = 0,
}) {
  if (discount.inPaisa <= 0 || subtotal.inPaisa <= 0) return true;
  final limit = role.maxDiscountBp > standingBp
      ? role.maxDiscountBp
      : standingBp;
  return discount.inPaisa * 10000 <= subtotal.inPaisa * limit;
}
