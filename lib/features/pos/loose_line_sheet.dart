import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// A loose line as the sheet hands it back: what it is called, how much at
/// what price, and the shop's unit if one was picked.
typedef LooseLine = ({
  String name,
  Qty qty,
  Rate rate,
  String? unitId,
  String? unitCode,
});

/// "Khula maal": a line with no item behind it (M37).
///
/// A kiryana sells a great deal that nobody ever entered as an item — onions
/// out of the sack, a length of rope, a bag of loose chana — and an Easy
/// Khata user put it plainly: three minutes to bill one kilo of onions. Here
/// it is a description (or nothing), a price, and Add. Nothing is made in
/// the catalogue, so a typo at the counter never becomes the twelfth "Pyaz"
/// in the item list, and nothing moves on a shelf.
///
/// [name] is what the cashier had typed into the search, when they came
/// here from a search that found nothing. A shop reporting to FBR is told
/// why it cannot have one ([refusedForFbr]) instead of being given a form
/// whose bill would be refused.
Future<LooseLine?> showLooseLineSheet(
  BuildContext context, {
  String name = '',
  bool refusedForFbr = false,
}) => showModalBottomSheet<LooseLine>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _LooseSheet(name: name, refusedForFbr: refusedForFbr),
);

class _LooseSheet extends ConsumerStatefulWidget {
  const _LooseSheet({required this.name, required this.refusedForFbr});

  final String name;
  final bool refusedForFbr;

  @override
  ConsumerState<_LooseSheet> createState() => _LooseSheetState();
}

class _LooseSheetState extends ConsumerState<_LooseSheet> {
  late final _name = TextEditingController(text: widget.name);
  final _rate = TextEditingController();
  final _qty = TextEditingController(text: '1');

  /// The shop's unit for it, if the cashier picked one. None is the usual
  /// case: "onions, Rs 150" is a whole amount, not a price per anything.
  String? _unitId;
  String? _unitCode;

  /// Set once Add has been tapped with something missing, so the field the
  /// cashier has not reached yet is not shouted at before they reach it.
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _qty.dispose();
    super.dispose();
  }

  /// What the line comes to, by the same rounding the bill will use, or
  /// null until there is a quantity and a price to make it of.
  Money? get _amount {
    final qty = Qty.tryParse(_qty.text);
    final rate = Rate.tryParse(_rate.text);
    if (qty == null || rate == null) return null;
    if (!qty.isPositive || rate.inMilliPaisa <= 0) return null;
    return rate.amountFor(qty);
  }

  void _add() {
    final s = AppStrings.of(context);
    final qty = Qty.tryParse(_qty.text);
    final rate = Rate.tryParse(_rate.text);
    if (_amount == null || qty == null || rate == null) {
      setState(() => _tried = true);
      return;
    }
    final typed = _name.text.trim();
    Navigator.of(context).pop<LooseLine>((
      // Never blank on the paper: a line with an amount and no words is the
      // one line on a receipt a customer queries.
      name: typed.isEmpty ? s.looseTitle : typed,
      qty: qty,
      rate: rate,
      unitId: _unitId,
      unitCode: _unitCode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final units = ref.watch(unitsProvider).valueOrNull ?? const [];
    final amount = _amount;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: t.accent),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  s.looseTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              BlIconButton(
                icon: Icons.close,
                label: s.actionClose,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space2),
          Text(s.looseHint, style: TextStyle(fontSize: 13, color: t.inkMuted)),
          const SizedBox(height: BlTokens.space4),
          if (widget.refusedForFbr)
            Container(
              padding: const EdgeInsets.all(BlTokens.space3),
              decoration: BoxDecoration(
                color: t.warningSurface,
                borderRadius: BorderRadius.circular(BlTokens.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 18, color: t.warning),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(
                      s.looseFbrRefused,
                      style: TextStyle(fontSize: 14, color: t.warning),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            BlField(
              controller: _name,
              label: s.looseName,
              hint: s.looseNameHint,
              autofocus: widget.name.isEmpty,
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _rate,
              label: s.looseRate,
              numeric: true,
              // Straight to the price when the name came from the search.
              autofocus: widget.name.isNotEmpty,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _qty,
              label: s.posQty,
              numeric: true,
              decimals: 3,
              onChanged: (_) => setState(() {}),
            ),
            if (units.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final u in units)
                    ChoiceChip(
                      label: Text(u.code),
                      selected: u.id == _unitId,
                      // Tapped again, it comes off: no unit is a choice too.
                      onSelected: (on) => setState(() {
                        _unitId = on ? u.id : null;
                        _unitCode = on ? u.code : null;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: BlTokens.space3),
            Text(
              s.looseAmount((amount ?? Money.zero).amountOnly),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.ink,
                fontFeatures: BlTokens.tabular,
              ),
            ),
            // Said to whoever reads the margins (M9's `seeCosts`). A
            // cashier has no profit figure to be misled by.
            if (services.can(Permission.seeCosts)) ...[
              const SizedBox(height: BlTokens.space2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: t.inkFaint),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(
                      s.looseNoCost,
                      style: TextStyle(fontSize: 12, color: t.inkFaint),
                    ),
                  ),
                ],
              ),
            ],
            if (_tried && amount == null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                s.looseNeedsPrice,
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.looseAdd,
              icon: Icons.add_shopping_cart,
              big: true,
              onPressed: _add,
            ),
          ],
        ],
      ),
    );
  }
}
