import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';

/// The pharmacy at the counter (M49): "% off MRP", as the shop's standing
/// discount and on a single line, and a pack scanned from a batch on hold.
///
/// Its own file so the counter's screens change by a line each.

/// [line] at the shop's standing discount off the printed price, when [rules]
/// say there is one and the item has a printed price: the price becomes the
/// MRP and the discount the shop's — or the customer's own, if that is more.
///
/// Only for a line just going on. A line the cashier has priced is theirs.
CartLine offMrpDefault(CartLine line, PharmacyRules? rules) {
  final mrp = line.item.mrp;
  if (rules == null || !rules.isPharmacy || rules.offMrpBp <= 0) return line;
  if (line.isLoose || mrp == null || line.isConverted) return line;
  return line.copyWith(
    rate: Rate.perUnit(mrp),
    discountBp: line.discountBp > rules.offMrpBp
        ? line.discountBp
        : rules.offMrpBp,
  );
}

/// The reason a pack scanned from [batch] of [item] may not be sold, when
/// that batch is on hold; null when it may.
Future<String?> heldPackReason(
  WidgetRef ref,
  ItemSummary item,
  String? batch,
) async {
  if (batch == null || !item.tracksBatch) return null;
  return ref.read(appServicesProvider).pharmacy.holdReasonOf(item.id, batch);
}

/// "% off MRP" on one line of the bill: the price becomes the printed price
/// and the discount the percentage typed, so the bill reads as a chemist's
/// does — "MRP 120, 10% off" — rather than as a price nobody can check.
///
/// Shown only for an item with a printed price.
class OffMrpField extends ConsumerStatefulWidget {
  const OffMrpField({super.key, required this.line});

  final CartLine line;

  @override
  ConsumerState<OffMrpField> createState() => _OffMrpFieldState();
}

class _OffMrpFieldState extends ConsumerState<OffMrpField> {
  late final TextEditingController _percent = TextEditingController(
    text: widget.line.discountBp == 0
        ? ''
        : Money.paisa(widget.line.discountBp).amountOnly,
  );
  String? _problem;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  void _apply() {
    final line = widget.line;
    final mrp = line.item.mrp;
    // A percentage typed as rupees and paisa: "10" is 1000 basis points,
    // "12.5" is 1250. No float is ever made of it.
    final bp = (Money.tryParse(_percent.text) ?? Money.zero).inPaisa;
    if (mrp == null || bp < 0 || bp > 10000) {
      setState(() => _problem = AppStrings.of(context).commonRequired);
      return;
    }
    var rate = Rate.perUnit(mrp);
    if (line.isConverted) {
      final units = ref.read(unitConverterProvider).valueOrNull;
      try {
        rate = units!.convertRate(
          rate,
          fromUnitId: line.item.unitId,
          toUnitId: line.sellingUnitId,
          itemId: line.item.id,
        );
      } on Object catch (error) {
        setState(() => _problem = '$error');
        return;
      }
    }
    final notifier = ref.read(cartProvider.notifier);
    notifier.setRate(line.item.id, rate);
    notifier.setDiscountBp(line.item.id, bp);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mrp = widget.line.item.mrp;
    if (widget.line.isLoose || mrp == null) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: BlField(
                  controller: _percent,
                  label: s.pharmacyOffMrp(mrp.amountOnly),
                  numeric: true,
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              BlButton(
                label: s.pharmacyOffMrpApply,
                kind: BlButtonKind.secondary,
                onPressed: _apply,
              ),
            ],
          ),
          if (_problem case final problem?)
            Text(problem, style: TextStyle(fontSize: 12, color: t.danger)),
        ],
      ),
    );
  }
}
