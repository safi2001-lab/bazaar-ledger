import 'package:pk_money/pk_money.dart';

/// Customers in groups, and a note about each that the counter sees (M40).
///
/// A wholesaler does not think of his khata as one list of four hundred
/// names. He thinks of it as Route 3 on Tuesday, the hotels on the canal
/// road, the retailers in Mohalla Gulberg — and the order-booker who goes
/// out with the van is handed exactly one of those. Vyapar keeps this as a
/// party setting and reports sale and purchase by it; until now the schema
/// had had a `parties.party_group` column since v1 that nothing wrote and
/// nothing read.
///
/// A group is a name and nothing else: free text, picked from the ones the
/// shop already uses or typed fresh. There is no table of groups to keep in
/// step with the parties, so a group exists exactly as long as somebody is
/// in it, and renaming one is moving its members.

/// The tidy form of a group name a shopkeeper typed.
///
/// Trimmed, runs of spaces made one, and blank made nothing at all: "  Route
/// 3 " and "Route 3" are one group, and a field cleared by the shopkeeper is
/// "no group", never a group called "".
String? partyGroupName(String? raw) {
  if (raw == null) return null;
  final tidy = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return tidy.isEmpty ? null : tidy;
}

/// How the khata list is put in order.
enum PartySort {
  /// A to Z, as a register is kept.
  name,

  /// Who owes the most, first: the list a shopkeeper reads before the
  /// evening round.
  balance,

  /// Whose oldest unpaid bill is oldest, first. The customer who owes
  /// Rs 3,000 since March is a different conversation from the one who owes
  /// Rs 40,000 since last week, and sorting by size puts the second first.
  oldestDue,
}

/// Which customers the khata list shows, and in what order.
///
/// A value, with equality, because it keys a provider family: two screens
/// asking for Route 3 by balance share one read.
final class PartyListFilter {
  const PartyListFilter({
    this.query = '',
    this.group,
    this.ungrouped = false,
    this.sort = PartySort.name,
  });

  /// A name or a phone number, as the search box takes it.
  final String query;

  /// Only the members of this group. Null is everyone.
  final String? group;

  /// Only the people in no group at all: the stragglers a shopkeeper sorting
  /// his khata into routes still has to place.
  final bool ungrouped;

  final PartySort sort;

  PartyListFilter copyWith({
    String? query,
    String? Function()? group,
    bool? ungrouped,
    PartySort? sort,
  }) => PartyListFilter(
    query: query ?? this.query,
    group: group == null ? this.group : group(),
    ungrouped: ungrouped ?? this.ungrouped,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is PartyListFilter &&
      other.query == query &&
      other.group == group &&
      other.ungrouped == ungrouped &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, group, ungrouped, sort);
}

/// One group, with who is in it and where the money stands.
final class PartyGroupSummary {
  const PartyGroupSummary({
    required this.name,
    required this.members,
    required this.receivable,
    required this.payable,
  });

  final String name;

  /// Customers and suppliers in it who are still in the khata. A party the
  /// shop has hidden keeps its group, so restoring them puts them back on
  /// their route, but is not counted here.
  final int members;

  /// What its members owe the shop: the sum of every balance that is owed,
  /// computed as the khata computes each one.
  final Money receivable;

  /// What the shop owes its members: deliveries not yet paid for, and money
  /// a customer paid ahead that the shop is holding for them.
  ///
  /// Never netted against [receivable]. A route where one retailer owes
  /// Rs 40,000 and another has Rs 5,000 on account is owed Rs 40,000 and
  /// owes Rs 5,000; "Rs 35,000" is a figure nobody on that route agreed to.
  final Money payable;
}

/// A group's trade over a period, for the reports (M40).
///
/// Sale/Purchase by Party Group is Vyapar's report; this is the read it
/// stands on. The trade is the period's; the balances are as they stand on
/// the khata today, the same figures every other screen shows, because a
/// balance as of a past date is a different and much more expensive read
/// that no screen has asked for yet.
final class PartyGroupTotals {
  const PartyGroupTotals({
    required this.group,
    required this.parties,
    required this.sales,
    required this.salesReturns,
    required this.purchases,
    required this.purchaseReturns,
    required this.receivable,
    required this.payable,
  });

  /// The group's name. Null is everybody who is in no group, so the rows
  /// always add up to the shop's own totals.
  final String? group;

  /// How many parties the row covers.
  final int parties;

  /// Posted sale bills dated in the period, at their totals.
  final Money sales;

  /// Posted returns from customers dated in the period.
  final Money salesReturns;

  /// Posted deliveries from suppliers dated in the period.
  final Money purchases;

  /// Posted returns to suppliers dated in the period.
  final Money purchaseReturns;

  /// What the group owes the shop now.
  final Money receivable;

  /// What the shop owes the group now.
  final Money payable;

  Money get netSales => sales - salesReturns;
  Money get netPurchases => purchases - purchaseReturns;
}
