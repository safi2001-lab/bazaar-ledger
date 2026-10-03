import 'package:pk_money/pk_money.dart';

/// One conversion as the database holds it: 1 [from] is [factorThousandths]
/// thousandths of [to].
///
/// So `dozen → pcs` carries 12000, because a dozen is twelve pieces and a
/// piece is a thousand thousandths. And `g → kg` carries 1, because a gram is
/// one thousandth of a kilo, which is exactly one unit of storage.
final class UnitEdge {
  const UnitEdge({
    required this.fromUnitId,
    required this.toUnitId,
    required this.factorThousandths,
    this.itemId,
  });

  final String fromUnitId;
  final String toUnitId;
  final int factorThousandths;

  /// Null for a conversion the whole shop uses. Set when one item's bori is a
  /// different size from another's — flour ships in 10, 40, 50 and 80 kg
  /// sacks and the shop decides which one it means.
  final String? itemId;
}

/// Raised when a quantity cannot be moved between two units exactly.
///
/// Deliberately not a rounding. A shopkeeper selling in maunds and stocking in
/// kilos is entitled to have the stock ledger and the invoice agree to the
/// last gram; the moment a conversion is allowed to round, the two drift and
/// nobody can tell which one is wrong.
final class UnitConversionException implements Exception {
  const UnitConversionException(this.message);
  final String message;
  @override
  String toString() => 'UnitConversionException: $message';
}

/// Moves a quantity between units, exactly or not at all.
///
/// The conversions form a small directed graph — `dozen → pcs`, `maund → kg`,
/// `tola → g` — and this walks it in either direction, because a shopkeeper
/// who buys in maunds and sells in kilos needs both. Every hop is integer
/// arithmetic and every hop must divide exactly; a path that would round is
/// not used, and if no exact path exists the conversion is refused rather than
/// approximated.
///
/// Why refusing is the right answer: a tola is 11.664 g. An item stocked in
/// kilos holds thousandths of a kilo, which is whole grams, and 11.664 g is
/// not a whole number of them. A jeweller therefore stocks in grams, where a
/// tola is exactly 11664 thousandths. Rounding instead would put 0.336 g of
/// gold a day into the difference between what the ledger says and what is in
/// the safe.
final class UnitConverter {
  UnitConverter(Iterable<UnitEdge> edges) : _edges = List.unmodifiable(edges);

  final List<UnitEdge> _edges;

  /// Every conversion held, the shop's and the items' own (M45): read once
  /// to index each item's packs, so a list of twenty thousand items does
  /// not scan every conversion for every row it shows.
  List<UnitEdge> get edges => _edges;

  /// Converts [qty], expressed in [fromUnitId], into [toUnitId].
  ///
  /// [itemId] selects that item's own conversions where it has them — its
  /// bori, its carton — falling back to the shop's.
  Qty convert(
    Qty qty, {
    required String fromUnitId,
    required String toUnitId,
    String? itemId,
  }) {
    if (fromUnitId == toUnitId) return qty;
    if (qty.isZero) return Qty.zero;

    final path = _path(fromUnitId, toUnitId, itemId);
    if (path == null) {
      throw UnitConversionException(
        'No conversion from $fromUnitId to $toUnitId'
        '${itemId == null ? '' : ' for item $itemId'}.',
      );
    }

    var value = qty.inThousandths;
    for (final hop in path) {
      value = hop.apply(value, fromUnitId: fromUnitId, toUnitId: toUnitId);
    }
    return Qty.raw(value);
  }

  /// The same price, expressed per a different unit.
  ///
  /// A rate is money per unit, so it scales the opposite way to a quantity: a
  /// dozen is twelve pieces, so twelve pieces of quantity become one dozen
  /// while a hundred rupees per piece becomes twelve hundred per dozen.
  ///
  /// Exact or refused, like everything else here. A price per unit that has
  /// to be rounded to change units is a price the line total and the unit
  /// price on the same piece of paper will disagree about — and the customer
  /// is holding that paper.
  Rate convertRate(
    Rate rate, {
    required String fromUnitId,
    required String toUnitId,
    String? itemId,
  }) {
    if (fromUnitId == toUnitId) return rate;

    // Both directions, because only one of them is a whole number.
    //
    // Going from a price per piece to a price per dozen is a multiplication:
    // a dozen holds twelve pieces. Going back is a division, and asking "how
    // many dozen in one piece" would be asking for a twelfth — which this
    // class refuses on principle, and rightly, for quantities. A price is the
    // other way up, so the divide is the exact operation.
    if (canConvert(
      Qty.one,
      fromUnitId: toUnitId,
      toUnitId: fromUnitId,
      itemId: itemId,
    )) {
      final perNew = convert(
        Qty.one,
        fromUnitId: toUnitId,
        toUnitId: fromUnitId,
        itemId: itemId,
      );
      final scaled = rate.inMilliPaisa * perNew.inThousandths;
      if (scaled % 1000 == 0) return Rate.raw(scaled ~/ 1000);
    }

    final perOld = convert(
      Qty.one,
      fromUnitId: fromUnitId,
      toUnitId: toUnitId,
      itemId: itemId,
    );
    final numerator = rate.inMilliPaisa * 1000;
    if (perOld.inThousandths == 0 || numerator % perOld.inThousandths != 0) {
      throw UnitConversionException(
        'A price per $fromUnitId does not come out even per $toUnitId. '
        'Rounding it would put the unit price and the line total on the same '
        'receipt out of step, and the customer is holding that paper.',
      );
    }
    return Rate.raw(numerator ~/ perOld.inThousandths);
  }

  /// Whether [qty] can be moved exactly, without throwing.
  ///
  /// For the counter, which must grey out a unit it cannot sell in rather
  /// than offer it and fail at the moment of saving the bill.
  bool canConvert(
    Qty qty, {
    required String fromUnitId,
    required String toUnitId,
    String? itemId,
  }) {
    try {
      convert(qty, fromUnitId: fromUnitId, toUnitId: toUnitId, itemId: itemId);
      return true;
    } on UnitConversionException {
      return false;
    }
  }

  /// Every unit [fromUnitId] can reach, in either direction.
  ///
  /// The list the counter offers for an item: its own unit plus everything
  /// the shop has said is the same thing measured differently.
  Set<String> reachableFrom(String fromUnitId, {String? itemId}) {
    final seen = <String>{fromUnitId};
    final queue = <String>[fromUnitId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in _edgesFor(itemId)) {
        for (final next in [
          if (edge.fromUnitId == current) edge.toUnitId,
          if (edge.toUnitId == current) edge.fromUnitId,
        ]) {
          if (seen.add(next)) queue.add(next);
        }
      }
    }
    return seen;
  }

  /// The conversions that belong to [itemId] alone: its packs (M53), its
  /// own size of bori. Not the shop's, which every item shares.
  List<UnitEdge> ownEdgesOf(String itemId) => [
    for (final e in _edges)
      if (e.itemId == itemId) e,
  ];

  /// An item's own conversions shadow the shop's for the same pair.
  ///
  /// One shop can sell flour in 50 kg bori and rice in 25 kg bori and call
  /// both "bori", because that is what the sacks say.
  List<UnitEdge> _edgesFor(String? itemId) {
    if (itemId == null) {
      return [
        for (final e in _edges)
          if (e.itemId == null) e,
      ];
    }
    final mine = [
      for (final e in _edges)
        if (e.itemId == itemId) e,
    ];
    final shadowed = {for (final e in mine) '${e.fromUnitId}>${e.toUnitId}'};
    return [
      ...mine,
      for (final e in _edges)
        if (e.itemId == null &&
            !shadowed.contains('${e.fromUnitId}>${e.toUnitId}') &&
            !shadowed.contains('${e.toUnitId}>${e.fromUnitId}'))
          e,
    ];
  }

  /// Breadth-first, so the shortest chain wins.
  ///
  /// Shortest matters for exactness as well as speed: every hop is a multiply
  /// and a divide, and each one is another chance to land on a remainder.
  List<_Hop>? _path(String from, String to, String? itemId) {
    final edges = _edgesFor(itemId);
    final previous = <String, _Hop>{};
    final seen = <String>{from};
    final queue = <String>[from];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == to) return _rebuild(previous, from, to);
      for (final edge in edges) {
        final next = edge.fromUnitId == current
            ? edge.toUnitId
            : edge.toUnitId == current
            ? edge.fromUnitId
            : null;
        if (next == null || !seen.add(next)) continue;
        previous[next] = _Hop(
          edge: edge,
          forward: edge.fromUnitId == current,
          from: current,
        );
        queue.add(next);
      }
    }
    return null;
  }

  List<_Hop> _rebuild(Map<String, _Hop> previous, String from, String to) {
    final hops = <_Hop>[];
    var at = to;
    while (at != from) {
      final hop = previous[at]!;
      hops.insert(0, hop);
      at = hop.from;
    }
    return hops;
  }
}

/// One step along the path, and the direction it is taken in.
final class _Hop {
  const _Hop({required this.edge, required this.forward, required this.from});

  final UnitEdge edge;

  /// True when walking `from → to`, false when walking it backwards. A
  /// shopkeeper who buys in maunds and sells in kilos needs both, and the
  /// database stores each pair once.
  final bool forward;

  final String from;

  int apply(int value, {required String fromUnitId, required String toUnitId}) {
    // Forward: one `from` is `factor` thousandths of `to`, so a quantity in
    // thousandths of `from` becomes value * factor / 1000.
    // Backward: the same division, the other way up.
    final numerator = forward ? value * edge.factorThousandths : value * 1000;
    final denominator = forward ? 1000 : edge.factorThousandths;

    if (numerator % denominator != 0) {
      throw UnitConversionException(
        'Converting $fromUnitId to $toUnitId would not come out even. '
        'A quantity that has to be rounded to change units is a quantity the '
        'stock ledger and the invoice will disagree about.',
      );
    }
    return numerator ~/ denominator;
  }
}
