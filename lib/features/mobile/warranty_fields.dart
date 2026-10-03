import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// How long an item's warranty runs, and whose it is (M50).
///
/// Shown in the item editor of a mobile or electronics shop, and on any
/// item that already carries a warranty wherever it is sold. Every bill
/// that sells it stamps the day the warranty ends on the line, and the bill
/// prints it: "Warranty till 3 Apr 2027". Changing it here changes no
/// phone already sold.
///
/// Reports every change and holds nothing back, as the medicine fields do:
/// the editor sends what it last heard, or nothing when nobody touched it.
class WarrantyFields extends ConsumerStatefulWidget {
  const WarrantyFields({super.key, this.initial, required this.onChanged});

  final ItemWarranty? initial;
  final ValueChanged<ItemWarranty> onChanged;

  @override
  ConsumerState<WarrantyFields> createState() => _WarrantyFieldsState();
}

class _WarrantyFieldsState extends ConsumerState<WarrantyFields> {
  late final _months = TextEditingController(
    text: switch (widget.initial) {
      final w? when !w.isNone => '${w.months}',
      _ => '',
    },
  );
  late WarrantyKind _kind = widget.initial?.kind ?? WarrantyKind.shop;
  String? _problem;

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  void _changed() {
    final text = _months.text.trim();
    final months = text.isEmpty ? 0 : int.tryParse(text);
    if (months == null || months < 0 || months > 120) {
      setState(() => _problem = AppStrings.of(context).mobileWarrantyMonthsBad);
      return;
    }
    if (_problem != null) setState(() => _problem = null);
    widget.onChanged(
      months == 0
          ? ItemWarranty.none
          : ItemWarranty(months: months, kind: _kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider).valueOrNull;
    final shows =
        (firm?.isMobileShop ?? false) ||
        firm?.businessKind == 'electronics' ||
        !(widget.initial?.isNone ?? true);
    if (!shows) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.mobileWarrantyTitle),
          const SizedBox(height: BlTokens.space2),
          Row(
            children: [
              Expanded(
                child: BlField(
                  controller: _months,
                  label: s.mobileWarrantyMonths,
                  hint: '12',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _changed(),
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              Expanded(
                child: DropdownButtonFormField<WarrantyKind>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.mobileWarrantyWhose),
                  items: [
                    DropdownMenuItem(
                      value: WarrantyKind.shop,
                      child: Text(s.mobileWarrantyShop),
                    ),
                    DropdownMenuItem(
                      value: WarrantyKind.brand,
                      child: Text(s.mobileWarrantyBrand),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _kind = value);
                    _changed();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space1),
          Text(
            _problem ?? s.mobileWarrantyNote,
            style: TextStyle(
              fontSize: 12,
              color: _problem == null ? t.inkMuted : t.danger,
            ),
          ),
        ],
      ),
    );
  }
}
