import 'package:pk_domain/pk_domain.dart';

/// Sends goods on a delivery challan: the cart priced exactly as a bill
/// would be, numbered, and taken off the shelf, with nothing owed until the
/// bill is made from it.
final class IssueChallanUseCase {
  const IssueChallanUseCase({
    required this.writer,
    this.calculator = const SaleCalculator(),
    this.builder = const DeliveryChallanBuilder(),
  });

  final ChallanWriter writer;
  final SaleCalculator calculator;
  final DeliveryChallanBuilder builder;

  /// Returns the challan's id and number.
  Future<({String id, String docNo})> call(
    ActorContext actor,
    SaleDraft draft,
  ) => writer.inTransaction(actor, (write) async {
    // Said in words before the calculator refuses it as a programming error.
    if (draft.lines.isEmpty) {
      throw const ChallanRefused('A challan needs at least one item.');
    }
    if (draft.partyId == null) {
      throw const ChallanRefused(
        'A challan has to name the customer the goods are going to.',
      );
    }
    // The goods leave at the average as it stands now, as a sale's do; the
    // bill made later carries this cost across rather than re-reading it.
    final costs = await write.averageCostFor({
      for (final l in draft.lines) l.itemId,
    });
    final costed = draft.withLines([
      for (final l in draft.lines)
        l.unitCost.isZero && costs[l.itemId] != null
            ? l.withUnitCost(costs[l.itemId]!)
            : l,
    ]);
    final calculated = calculator.calculate(
      costed,
      await write.taxContextFor(costed.partyId),
    );
    final number = await write.nextNumber('delivery_challan');
    final journalNumber = await write.nextNumber('journal_entry');
    final posting = builder.build(
      actor: actor,
      draft: costed,
      calculated: calculated,
      number: number,
      journalNumber: journalNumber,
    );
    return (id: await write.apply(posting), docNo: number.formatted);
  });
}
