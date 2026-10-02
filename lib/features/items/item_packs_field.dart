import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// A unit as the units provider hands it over.
typedef ShopUnit = ({String id, String code, String name, int decimals});

/// The packs an item comes in, in its editor (M53): "1 carton = 24 pcs",
/// "1 bori = 50 kg", each with a way to take it off, and a way to add one.
///
/// Only the shop's pack units are offered ([packUnitCodes]), and only those
/// the item does not already have and is not counted in. Nothing is written
/// here: the editor hands the list to the catalogue writer with the rest of
/// the item, in one transaction.
class ItemPacksField extends StatelessWidget {
  const ItemPacksField({
    super.key,
    required this.packs,
    required this.baseUnitId,
    required this.units,
    required this.onChanged,
  });

  final List<ItemPack> packs;
  final String baseUnitId;
  final List<ShopUnit> units;
  final ValueChanged<List<ItemPack>> onChanged;

  String _code(String unitId) =>
      [
        for (final u in units)
          if (u.id == unitId) u.code,
      ].firstOrNull ??
      '';

  List<ShopUnit> get _addable => [
    for (final code in packUnitCodes)
      for (final u in units)
        if (u.code == code &&
            u.id != baseUnitId &&
            !packs.any((p) => p.unitId == u.id))
          u,
  ];

  Future<void> _add(BuildContext context) async {
    final pack = await showDialog<ItemPack>(
      context: context,
      builder: (_) =>
          _PackDialog(units: _addable, baseUnitCode: _code(baseUnitId)),
    );
    if (pack != null) onChanged([...packs, pack]);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final base = _code(baseUnitId);
    final addable = _addable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.itemPacksTitle,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        const SizedBox(height: BlTokens.space1),
        Text(
          s.itemPacksHint(base),
          style: TextStyle(fontSize: 12, color: t.inkMuted),
        ),
        for (final pack in packs)
          Row(
            children: [
              Expanded(
                child: Text(
                  '1 ${_code(pack.unitId)} = ${pack.size.display} $base',
                  style: TextStyle(fontSize: 15, color: t.ink),
                ),
              ),
              BlIconButton(
                icon: Icons.remove_circle_outline,
                label: s.itemPackRemove,
                colour: t.danger,
                onPressed: () => onChanged([
                  for (final p in packs)
                    if (p.unitId != pack.unitId) p,
                ]),
              ),
            ],
          ),
        const SizedBox(height: BlTokens.space2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: addable.isEmpty
              ? Text(
                  s.itemPackNoneLeft,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                )
              : TextButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_box_outlined),
                  label: Text(s.itemPackAdd),
                ),
        ),
      ],
    );
  }
}

/// Which pack, and how much of the item one of it holds.
class _PackDialog extends StatefulWidget {
  const _PackDialog({required this.units, required this.baseUnitCode});

  final List<ShopUnit> units;
  final String baseUnitCode;

  @override
  State<_PackDialog> createState() => _PackDialogState();
}

class _PackDialogState extends State<_PackDialog> {
  late String _unitId = widget.units.first.id;
  final _size = TextEditingController();

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  String get _code => widget.units.firstWhere((u) => u.id == _unitId).code;

  void _done() {
    final size = Qty.tryParse(_size.text);
    if (size == null || !size.isPositive) return;
    Navigator.of(
      context,
    ).pop(ItemPack(unitId: _unitId, unitCode: _code, size: size));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.itemPackAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _unitId,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.itemPackUnit),
              items: [
                for (final u in widget.units)
                  DropdownMenuItem(
                    value: u.id,
                    child: Text('${u.name} (${u.code})'),
                  ),
              ],
              onChanged: (v) => setState(() => _unitId = v ?? _unitId),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _size,
              label: s.itemPackSize(_code, widget.baseUnitCode),
              numeric: true,
              decimals: 3,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: (Qty.tryParse(_size.text)?.isPositive ?? false)
              ? _done
              : null,
          child: Text(s.actionAdd),
        ),
      ],
    );
  }
}
