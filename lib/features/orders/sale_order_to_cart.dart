import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';

/// Puts what is still to go of sale order [view] on the counter (M41), to
/// be billed from the payment sheet as a quotation is (M25): at the prices
/// the customer was promised, for the customer who ordered, linked back to
/// the order so the bill made there says where it came from and takes the
/// advance paid on it.
///
/// Through the cart's own `loadQuotation`, which is the counter's one way
/// in for a document a bill is made from; an order is one more such
/// document, and nothing about the cart had to change for it. The write
/// path also sends an order out on a challan, and since M54 the payment
/// sheet offers it for an order (the cart now knows what paper it holds,
/// `Cart.sourceType`); the bill made from that challan takes the advance.
///
/// Returns why it could not, in words, or null when the counter has it.
Future<String?> takeSaleOrderToCounter(
  WidgetRef ref,
  AppStrings s,
  OrderView view,
) async {
  if (!ref.read(cartProvider).isEmpty) return s.quotationCounterBusy;
  final services = ref.read(appServicesProvider);
  final firm = await ref.read(firmProvider.future);
  if (firm == null) return s.commonNothingSaved;
  final lines = <(ItemSummary, QuotedLine)>[];
  for (final l in view.lines) {
    if (l.isDone) continue;
    final item = await services.queries.itemById(firm.id, l.itemId);
    if (item == null) return s.quotationItemGone;
    // In the unit it was ordered in while what is left comes out whole in
    // it; otherwise in the item's own unit, at the same price per piece.
    final (qty, unitId, unitCode, rate) = switch (l.pendingInOrderUnit) {
      final q? => (q, l.unitId, l.unitCode, l.rate),
      null => (l.pendingBase, item.unitId, item.unitCode, l.baseRate),
    };
    lines.add((
      item,
      QuotedLine(
        itemId: l.itemId,
        qty: qty,
        unitId: unitId.isEmpty ? null : unitId,
        unitCode: unitCode,
        rate: rate,
      ),
    ));
  }
  if (lines.isEmpty) return s.orderNothingLeft;
  final party = await services.queries.partyById(firm.id, view.row.partyId);
  ref
      .read(cartProvider.notifier)
      .loadQuotation(
        QuotationRow(
          id: view.row.id,
          docNo: view.row.docNo,
          date: view.row.date,
          total: view.row.total,
          partyId: view.row.partyId,
          partyName: view.row.partyName,
          docType: view.row.kind.docType,
        ),
        lines,
        party: party,
      );
  return null;
}
