import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// One line of a delivery as it actually arrived (M41): a line filled in
/// from the purchase order, changed to what the supplier's bill says.
///
/// The quantity is in the unit the line is in — the order's cartons stay
/// cartons — and the rate is per that unit, so it is set beside the rate
/// the order quoted and a difference is seen at the door. A batch and its
/// expiry are asked for an item kept by batch, and serial numbers for one
/// kept by serial, exactly as when the line is added by hand.
Future<PurchaseLineDraft?> showDeliveryLineSheet(
  BuildContext context, {
  required PurchaseLineDraft line,
  Rate? ordered,
}) => showModalBottomSheet<PurchaseLineDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _DeliveryLineSheet(line: line, ordered: ordered),
);

class _DeliveryLineSheet extends ConsumerStatefulWidget {
  const _DeliveryLineSheet({required this.line, required this.ordered});

  final PurchaseLineDraft line;
  final Rate? ordered;

  @override
  ConsumerState<_DeliveryLineSheet> createState() => _DeliveryLineSheetState();
}

class _DeliveryLineSheetState extends ConsumerState<_DeliveryLineSheet> {
  late final _qty = TextEditingController(text: widget.line.qty.display);
  late final _rate = TextEditingController(text: widget.line.rate.amountOnly);
  late final _batch = TextEditingController(text: widget.line.batchNo ?? '');
  late final _expiry = TextEditingController(
    text: widget.line.expiry?.value ?? '',
  );
  late final _serials = TextEditingController(
    text: widget.line.serials.join('\n'),
  );
  String? _problem;

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    _batch.dispose();
    _expiry.dispose();
    _serials.dispose();
    super.dispose();
  }

  Future<void> _done(ItemSummary? item) async {
    final s = AppStrings.of(context);
    final line = widget.line;
    final serials = [
      for (final l in _serials.text.split(RegExp(r'[\n,]')))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final qty = item?.tracksSerial ?? false
        ? Qty.units(serials.length)
        : Qty.tryParse(_qty.text.trim());
    final rate = Rate.tryParse(_rate.text.trim());
    if (qty == null || !qty.isPositive || rate == null || rate.isZero) {
      setState(() => _problem = s.orderItemNeeds);
      return;
    }
    final expiry = BusinessDate.tryParse(_expiry.text.trim());
    if ((item?.tracksBatch ?? false) &&
        (_batch.text.trim().isEmpty ||
            (_expiry.text.trim().isNotEmpty && expiry == null))) {
      setState(() => _problem = s.purchaseBatchNeeded);
      return;
    }
    var base = qty;
    if (item != null && line.unitId != item.unitId) {
      try {
        final units = await ref.read(unitConverterProvider.future);
        base = units.convert(
          qty,
          fromUnitId: line.unitId,
          toUnitId: item.unitId,
          itemId: item.id,
        );
      } on Object {
        setState(() => _problem = s.orderItemUnitInexact);
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      PurchaseLineDraft(
        itemId: line.itemId,
        itemName: line.itemName,
        qty: qty,
        baseQty: base,
        unitId: line.unitId,
        unitCode: line.unitCode,
        rate: rate,
        batchNo: item?.tracksBatch ?? false ? _batch.text.trim() : null,
        expiry: item?.tracksBatch ?? false ? expiry : null,
        serials: serials,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final line = widget.line;
    final item = ref.watch(_itemProvider(line.itemId)).valueOrNull;
    final rate = Rate.tryParse(_rate.text.trim());

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            line.itemName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          if (widget.ordered case final o?)
            Text(
              s.purchaseOrderedRate(o.amountOnly, line.unitCode),
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
          const SizedBox(height: BlTokens.space3),
          Row(
            children: [
              if (!(item?.tracksSerial ?? false)) ...[
                Expanded(
                  child: BlField(
                    controller: _qty,
                    label: '${s.posQty} (${line.unitCode})',
                    numeric: true,
                    decimals: 3,
                    onChanged: (_) => setState(() => _problem = null),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
              ],
              Expanded(
                child: BlField(
                  controller: _rate,
                  label: s.orderRate,
                  numeric: true,
                  onChanged: (_) => setState(() => _problem = null),
                ),
              ),
            ],
          ),
          if (rate != null && rateDiffers(rate, widget.ordered))
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space2),
              child: Text(
                s.purchaseRateDiffers(
                  rate.amountOnly,
                  widget.ordered!.amountOnly,
                ),
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ),
          if (item?.tracksBatch ?? false) ...[
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlField(controller: _batch, label: s.purchaseBatch),
                ),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: BlField(
                    controller: _expiry,
                    label: s.purchaseExpiry,
                    hint: 'YYYY-MM-DD',
                  ),
                ),
              ],
            ),
          ],
          if (item?.tracksSerial ?? false) ...[
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _serials,
              label: s.purchaseSerials,
              maxLines: 5,
              onChanged: (_) => setState(() => _problem = null),
            ),
          ],
          if (_problem != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(_problem!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.actionSave,
            icon: Icons.check,
            big: true,
            onPressed: () => _done(item),
          ),
        ],
      ),
    );
  }
}

/// The item a delivery line is of, for whether it is kept by batch or by
/// serial.
final _itemProvider = FutureProvider.autoDispose.family<ItemSummary?, String>((
  ref,
  itemId,
) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  return services.queries.itemById(firm.id, itemId);
});
