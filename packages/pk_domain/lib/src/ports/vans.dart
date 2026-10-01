import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../time/clock.dart';

/// A van, as the screens list it.
final class VanView {
  const VanView({
    required this.id,
    required this.name,
    required this.locationCode,
    this.riderUserId,
    this.riderName,
  });

  final String id;
  final String name;
  final String locationCode;
  final String? riderUserId;
  final String? riderName;
}

/// Goods on a van.
typedef VanStock = ({String itemId, String name, String unitCode, Qty qty});

/// A settled day.
final class VanSettlementView {
  const VanSettlementView({
    required this.date,
    required this.expected,
    required this.counted,
    required this.linesReturned,
  });

  final BusinessDate date;
  final Money expected;
  final Money counted;
  final int linesReturned;

  Money get difference => counted - expected;
}

/// One van's day so far.
final class VanDay {
  const VanDay({
    required this.salesCount,
    required this.expectedCash,
    required this.stock,
    this.settled,
  });

  final int salesCount;

  /// The cash the van's sales today took, which the rider should hand over.
  final Money expectedCash;
  final List<VanStock> stock;

  /// Today's settlement, once it is done.
  final VanSettlementView? settled;
}

/// Writing vans and settling their days.
abstract interface class VanWriter {
  Future<String> addVan(
    ActorContext actor, {
    required String name,
    String? riderUserId,
  });

  /// Settles today for [vanId] — or an earlier [day] a rider came back too
  /// late to settle (M27): the rider's [counted] cash against what the van's
  /// cash sales took that day, and, when [returnStock], every unsold piece
  /// back to the shop floor. Once a day.
  Future<VanSettlementView> settle(
    ActorContext actor,
    String vanId, {
    required Money counted,
    bool returnStock = true,
    BusinessDate? day,
  });
}
