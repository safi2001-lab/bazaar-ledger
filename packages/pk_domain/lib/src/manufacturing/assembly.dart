/// Making one thing out of others (M17).
///
/// A masala maker mixes bulk spices into packs, a bakery turns flour and
/// ghee into biscuits, a mobile shop puts a charger and a cover into a
/// bundle. A bill of materials writes down what one batch takes; an
/// assembly is one production run of it. The components leave the shelf at
/// what they cost, the finished goods arrive at that cost plus the work, and
/// the moving average of the finished item moves exactly as a delivery
/// would move it.
library;

import 'package:pk_money/pk_money.dart';

import '../costing/moving_average.dart';

/// One component of a batch.
final class BomLineDraft {
  const BomLineDraft({required this.itemId, required this.qty});

  final String itemId;

  /// Per batch, in the component's base unit.
  final Qty qty;
}

/// What one batch of [outputItemId] takes.
final class BomDraft {
  const BomDraft({
    required this.name,
    required this.outputItemId,
    required this.outputQty,
    required this.lines,
    this.overhead = Money.zero,
  });

  final String name;
  final String outputItemId;

  /// How much one batch makes.
  final Qty outputQty;

  /// Work, packets, gas: a batch's cost beyond its components.
  final Money overhead;
  final List<BomLineDraft> lines;

  /// Throws [AssemblyRefused] unless this is a recipe that can be made.
  void check() {
    if (name.trim().isEmpty) {
      throw const AssemblyRefused('Give the recipe a name.');
    }
    if (!outputQty.isPositive) {
      throw const AssemblyRefused('A batch has to make something.');
    }
    if (overhead.isNegative) {
      throw const AssemblyRefused('Work cannot cost less than nothing.');
    }
    if (lines.isEmpty) {
      throw const AssemblyRefused('A recipe needs at least one component.');
    }
    final seen = <String>{};
    for (final line in lines) {
      if (!line.qty.isPositive) {
        throw const AssemblyRefused('Every component needs a quantity.');
      }
      if (line.itemId == outputItemId) {
        throw const AssemblyRefused('An item cannot be made out of itself.');
      }
      if (!seen.add(line.itemId)) {
        throw const AssemblyRefused(
          'The same component is in the recipe twice; put it in once.',
        );
      }
    }
  }
}

/// A component as it stands on the shelf now.
final class ComponentOnHand {
  const ComponentOnHand({
    required this.itemId,
    required this.name,
    required this.onHand,
    required this.avgCost,
    required this.unitCode,
  });

  final String itemId;
  final String name;
  final Qty onHand;
  final Rate avgCost;
  final String unitCode;
}

/// One component leaving the shelf in a run.
typedef ComponentUse = ({String itemId, Qty qty, Rate cost, Money value});

/// What one production run does.
final class AssemblyPlan {
  const AssemblyPlan({
    required this.outputQty,
    required this.uses,
    required this.componentsCost,
    required this.overhead,
    required this.outputAvgAfter,
  });

  final Qty outputQty;
  final List<ComponentUse> uses;
  final Money componentsCost;
  final Money overhead;

  Money get totalCost => componentsCost + overhead;

  /// The finished item's average cost once the run is on the shelf.
  final Rate outputAvgAfter;
}

/// Plans [runs] batches of [bom] from what is on the shelf.
///
/// Refuses, naming every component that is short, rather than let the shelf
/// go negative: a masala pack made from spices the shop does not have is a
/// stock figure nobody can explain.
AssemblyPlan planAssembly({
  required BomDraft bom,
  required int runs,
  required Map<String, ComponentOnHand> components,
  required CostPosition output,
}) {
  bom.check();
  if (runs < 1) {
    throw const AssemblyRefused('Make at least one batch.');
  }
  final uses = <ComponentUse>[];
  final short = <String>[];
  for (final line in bom.lines) {
    final c = components[line.itemId];
    if (c == null) {
      throw const AssemblyRefused(
        'A component of this recipe is no longer in the catalogue.',
      );
    }
    final needed = line.qty * runs;
    if (c.onHand < needed) {
      short.add(
        '${c.name}: ${needed.display} ${c.unitCode} needed, '
        '${c.onHand.display} on hand',
      );
      continue;
    }
    uses.add((
      itemId: c.itemId,
      qty: needed,
      cost: c.avgCost,
      value: c.avgCost.amountFor(needed),
    ));
  }
  if (short.isNotEmpty) {
    throw AssemblyRefused('Not enough to make this:\n${short.join('\n')}');
  }
  final componentsCost = Money.sum([for (final u in uses) u.value]);
  final overhead = bom.overhead * runs;
  final outputQty = bom.outputQty * runs;
  final change = receiveStock(
    before: output,
    qtyIn: outputQty,
    landedCost: componentsCost + overhead,
  );
  return AssemblyPlan(
    outputQty: outputQty,
    uses: uses,
    componentsCost: componentsCost,
    overhead: overhead,
    outputAvgAfter: change.after.avg,
  );
}

/// Why a recipe or a run was refused, in words.
final class AssemblyRefused implements Exception {
  const AssemblyRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
