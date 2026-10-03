import 'package:flutter/material.dart';
import 'package:pk_domain/pk_domain.dart'
    show CountingLadder, PackPrice, Qty, Rate, shortUnitName;

import '../l10n/app_strings.dart';
import 'components.dart';
import 'tokens.dart';

/// The quantity box that takes "2 ctn 5" as readily as "53" (M45).
///
/// A shop counts a shelf the way it is stacked, two cartons and five loose,
/// and until now had to multiply in its head to type it: 53. Here the box
/// reads what was typed in the item's own units — "2 ctn 5", "2c 5p", "1 kg
/// 250", "2 peti 5 adad" — and says back underneath what it understood,
/// "Yani 2 ctn + 5 pcs (53 pcs)", before anything is saved. A figure on its
/// own still means what it always meant, the box's own unit.
///
/// The keypad stays the number pad, which is what a cashier types nine
/// times in ten. Letters are a tap away on the key at the end of the box,
/// and for the commonest case not needed at all: the steppers under it add
/// or take off a whole carton or a single piece, and write the count in the
/// box in words.
///
/// What it does NOT do is decide anything. The box hands back the text; the
/// screen reads it with the same ladder and decides what the line becomes,
/// exactly or not at all.
class CountedQtyField extends StatefulWidget {
  const CountedQtyField({
    super.key,
    required this.controller,
    required this.label,
    required this.counting,
    this.unitSize,
    this.autofocus = false,
    this.onChanged,
    this.problem,
  });

  final TextEditingController controller;
  final String label;

  /// The item's units, for reading what is typed and for the steppers.
  final CountingLadder counting;

  /// How much one of the box's own unit holds in the item's base unit: one
  /// for pieces, 24 when the line is in cartons of 24. A figure typed alone
  /// is in that unit. Null when it cannot be known, and then a figure alone
  /// is simply not echoed back.
  final Qty? unitSize;

  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Why what was typed was refused, from the screen that tried to use it.
  final String? problem;

  @override
  State<CountedQtyField> createState() => _CountedQtyFieldState();
}

class _CountedQtyFieldState extends State<CountedQtyField> {
  bool _letters = false;

  CountingLadder get _counting => widget.counting;

  /// What is in the box, in the item's base unit; null when it cannot be
  /// read, or is a figure alone in a unit of unknown size.
  Qty? get _typed {
    final text = widget.controller.text;
    if (text.trim().isEmpty) return Qty.zero;
    final read = _counting.read(text);
    if (read == null) return null;
    if (!read.bare) return read.qty;
    final size = widget.unitSize;
    if (size == null) return null;
    final scaled = read.qty.inThousandths * size.inThousandths;
    return scaled % 1000 == 0 ? Qty.raw(scaled ~/ 1000) : null;
  }

  void _step(Qty by) {
    final now = _typed ?? Qty.zero;
    var next = now + by;
    if (next.isNegative) next = Qty.zero;
    final text = _counting.words(next);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
    widget.onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final text = widget.controller.text;
    final read = text.trim().isEmpty ? null : _counting.read(text);
    final base = read == null ? null : _typed;
    final counted = base == null ? null : _counting.words(base);
    final figure = base == null
        ? null
        : _counting.baseCode.isEmpty
        ? base.display
        : '${base.display} ${_counting.baseCode}';
    // Said back only when it says something the figure does not: "Yani 2
    // ctn + 5 pcs (53 pcs)", not "Yani 5 pcs (5 pcs)".
    final echo = counted == null || counted == figure
        ? null
        : s.qtyCountedAs(counted, figure!);
    final problem =
        widget.problem ??
        (text.trim().isNotEmpty && read == null ? s.qtyNotUnderstood : null);

    final steps = [
      for (final rung in _counting.rungs.take(2))
        (rung.unitCode ?? rung.unitId, rung.size),
      if (_counting.baseCode.isNotEmpty) (_counting.baseCode, Qty.one),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          keyboardType: _letters
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 16,
            color: t.ink,
            fontWeight: FontWeight.w600,
            fontFeatures: BlTokens.tabular,
          ),
          onChanged: (value) {
            setState(() {});
            widget.onChanged?.call(value);
          },
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: problem,
            errorMaxLines: 3,
            helperText: echo,
            helperMaxLines: 2,
            suffixIcon: BlIconButton(
              icon: _letters ? Icons.dialpad : Icons.abc,
              label: _letters ? s.qtyKeypadNumbers : s.qtyKeypadLetters,
              onPressed: () => setState(() => _letters = !_letters),
            ),
          ),
        ),
        // The steppers, for an item that has a pack to step by.
        if (_counting.hasPacks) ...[
          const SizedBox(height: BlTokens.space2),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              for (final (code, size) in steps) ...[
                _Step(
                  text: s.qtyStepDown(shortUnitName(code)),
                  label: s.qtyStepDownLabel(shortUnitName(code)),
                  onTap: () => _step(-size),
                ),
                _Step(
                  text: s.qtyStepUp(shortUnitName(code)),
                  label: s.qtyStepUpLabel(shortUnitName(code)),
                  onTap: () => _step(size),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.text, required this.label, required this.onTap});

  final String text;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: ActionChip(label: Text(text), onPressed: onTap),
  );
}

/// The carton calculator (M45): a price typed per one unit, said per the
/// item's other units. "1 pcs = Rs 40.00 · 1 ctn = Rs 960.00".
///
/// The thing a wholesaler keeps a calculator beside the till for. Only for
/// an item with a pack, and only when the price has been typed; a price
/// that does not come out even per piece is shown to the paisa with "≈",
/// because this is a figure to read, never one charged.
class PackPriceHint extends StatelessWidget {
  const PackPriceHint({
    super.key,
    required this.counting,
    required this.rate,
    required this.per,
  });

  final CountingLadder counting;

  /// The price typed, per [per] of the base unit.
  final Rate? rate;
  final Qty? per;

  @override
  Widget build(BuildContext context) {
    final r = rate;
    final p = per;
    if (!counting.hasPacks || r == null || r.isZero || p == null) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    String said(PackPrice price) {
      final unit = shortUnitName(price.unitCode);
      final amount = price.rate.amountOnly;
      return price.exact
          ? s.qtyPriceEach(unit, amount)
          : s.qtyPriceAbout(unit, amount);
    }

    final prices = counting.pricesFrom(r, per: p);
    if (prices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space1),
      child: Text(
        prices.map(said).join('  ·  '),
        style: TextStyle(fontSize: 13, color: context.bl.inkMuted),
      ),
    );
  }
}
