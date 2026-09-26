import 'package:pk_domain/pk_domain.dart';

/// Writes a quotation: the cart priced exactly as a bill would be, numbered,
/// and kept, with nothing leaving the shelf and nothing owed.
final class SaveQuotationUseCase {
  const SaveQuotationUseCase({
    required this.writer,
    this.calculator = const SaleCalculator(),
    this.builder = const QuotationBuilder(),
  });

  final QuotationWriter writer;
  final SaleCalculator calculator;
  final QuotationBuilder builder;

  /// Returns the quotation's id and number.
  Future<({String id, String docNo})> call(
    ActorContext actor,
    SaleDraft draft,
  ) => writer.inTransaction(actor, (write) async {
    // Said in words before the calculator refuses it as a programming error.
    if (draft.lines.isEmpty) {
      throw const QuotationRefused('A quotation needs at least one item.');
    }
    final calculated = calculator.calculate(
      draft,
      await write.taxContextFor(draft.partyId),
    );
    final number = await write.nextNumber('quotation');
    final posting = builder.build(
      actor: actor,
      draft: draft,
      calculated: calculated,
      number: number,
    );
    return (id: await write.apply(posting), docNo: number.formatted);
  });
}
