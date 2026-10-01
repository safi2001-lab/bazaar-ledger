import 'package:pk_domain/pk_domain.dart';

/// Rings up a sale.
///
/// This is the reference use case. Every later one — purchases, returns,
/// payments, journal vouchers — copies its shape exactly:
///
///  1. everything happens inside one transaction;
///  2. the numbers are computed by a pure function that can be tested without
///     a database;
///  3. the rows are described as a value before any of them is written;
///  4. the entry is proved to balance before the write is attempted;
///  5. the caller receives what was actually written, or an exception.
///
/// There is no path through this method that reports success without a commit.
/// The previous build's checkout showed a SnackBar reading "Sale processed!"
/// and wrote nothing at all — `grep InvoicesCompanion.insert lib/` returned no
/// hits anywhere in the repository. What made that possible was not
/// carelessness; it was that nothing in the architecture required the write to
/// exist. Here the return value comes from the writer, so a use case that
/// wrote nothing has nothing to return.
final class PostSaleUseCase {
  const PostSaleUseCase({
    required this.writer,
    this.calculator = const SaleCalculator(),
    this.builder = const SalePostingBuilder(),
  });

  final SaleWriter writer;
  final SaleCalculator calculator;
  final SalePostingBuilder builder;

  Future<PostedSale> call(ActorContext actor, SaleDraft draft) {
    return writer.inTransaction(actor, (write) async {
      final taxContext = await write.taxContextFor(draft.partyId);

      // Cost is captured at post time, from the weighted average as it stands
      // now. Bill-wise profit reads what the goods cost on the day they were
      // sold, never a recomputation against today's cost — otherwise last
      // month's margin changes every time a new consignment arrives.
      final costs = await write.averageCostFor({
        for (final l in draft.lines) l.itemId,
      });
      // Through withLines, so nothing else on the draft — where the goods
      // leave from included — is lost on the way.
      final priced = draft.withLines([
        for (final l in draft.lines)
          l.unitCost.isZero && costs[l.itemId] != null
              ? _withCost(l, costs[l.itemId]!)
              : l,
      ]);

      final calculated = calculator.calculate(priced, taxContext);

      final invoiceNumber = await write.nextNumber('sale_invoice');
      final journalNumber = await write.nextNumber('journal_entry');
      // One receipt number per payment that will actually be written, asked
      // of the calculator rather than counted off the draft. A tender that
      // settles nothing and gives no change is not a payment, and drawing a
      // number for it leaves a permanent gap in the receipt series on the
      // success path — the one place a rollback test would never look.
      final paymentNumbers = <AllocatedNumber>[
        for (var i = 0; i < calculated.tenders.length; i++)
          await write.nextNumber('payment_in'),
      ];

      final ledgerAccounts = await write.ledgerAccountsFor({
        for (final t in priced.tenders) t.paymentAccountId,
      });

      // A bill made from a challan sells what the challan already sent; a
      // bill for several, what they sent between them (M25).
      final sent = <ChallanGoods>[];
      for (final id in draft.sourceIds) {
        if (await write.deliveredOn(id) case final goods?) sent.add(goods);
      }
      if (sent.isNotEmpty && sent.length != draft.sourceIds.length) {
        throw const ChallanRefused(
          'Only challans can be billed together on one bill.',
        );
      }
      final delivered = sent.isEmpty ? null : ChallanGoods.combine(sent);

      final posting = builder.build(
        actor: actor,
        draft: priced,
        calculated: calculated,
        invoiceNumber: invoiceNumber,
        journalNumber: journalNumber,
        paymentNumbers: paymentNumbers,
        ledgerAccountByPaymentAccount: ledgerAccounts,
        delivered: delivered,
      );

      return write.apply(posting);
    });
  }

  static SaleLineDraft _withCost(SaleLineDraft line, Rate cost) =>
      SaleLineDraft(
        itemId: line.itemId,
        itemName: line.itemName,
        itemCode: line.itemCode,
        hsCode: line.hsCode,
        description: line.description,
        qty: line.qty,
        baseQty: line.baseQty,
        unitId: line.unitId,
        unitCode: line.unitCode,
        rate: line.rate,
        discountBp: line.discountBp,
        explicitDiscount: line.explicitDiscount,
        unitCost: cost,
        mrp: line.mrp,
        isThirdSchedule: line.isThirdSchedule,
        taxRuleId: line.taxRuleId,
        lotId: line.lotId,
        isFreeItem: line.isFreeItem,
        tracksStock: line.tracksStock,
      );
}
