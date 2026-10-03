import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What an item is as a medicine (M49): its salt and strength, who made it,
/// and its Schedule class.
///
/// Shown in the item editor of a shop that calls itself a pharmacy, and on
/// any item that already is a medicine wherever it is sold, so a general
/// store that stocks Panadol can still say it is paracetamol. It reports
/// every change and holds nothing back: the editor sends what it last heard,
/// or nothing at all when the shopkeeper never touched it, so a save that
/// changes the price never rewrites the salt.
class MedicineFields extends ConsumerStatefulWidget {
  const MedicineFields({super.key, this.initial, required this.onChanged});

  final MedicineDetails? initial;
  final ValueChanged<MedicineDetails> onChanged;

  @override
  ConsumerState<MedicineFields> createState() => _MedicineFieldsState();
}

class _MedicineFieldsState extends ConsumerState<MedicineFields> {
  late final _generic = TextEditingController(
    text: widget.initial?.genericName ?? '',
  );
  late final _strength = TextEditingController(
    text: widget.initial?.strength ?? '',
  );
  late final _maker = TextEditingController(
    text: widget.initial?.manufacturer ?? '',
  );
  late ScheduleClass? _schedule = widget.initial?.schedule;

  @override
  void dispose() {
    _generic.dispose();
    _strength.dispose();
    _maker.dispose();
    super.dispose();
  }

  void _changed() => widget.onChanged(
    MedicineDetails(
      genericName: _generic.text,
      strength: _strength.text,
      manufacturer: _maker.text,
      schedule: _schedule,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final pharmacy = ref.watch(firmProvider).valueOrNull?.isPharmacy ?? false;
    if (!pharmacy && widget.initial == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.pharmacyMedicineTitle),
          const SizedBox(height: BlTokens.space2),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: BlField(
                  controller: _generic,
                  label: s.pharmacyGeneric,
                  hint: s.pharmacyGenericHint,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _changed(),
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              Expanded(
                flex: 2,
                child: BlField(
                  controller: _strength,
                  label: s.pharmacyStrength,
                  hint: '500 mg',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _changed(),
                ),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _maker,
            label: s.pharmacyManufacturer,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _changed(),
          ),
          const SizedBox(height: BlTokens.space3),
          DropdownButtonFormField<ScheduleClass?>(
            initialValue: _schedule,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.pharmacySchedule),
            items: [
              DropdownMenuItem(child: Text(s.pharmacyScheduleNone)),
              DropdownMenuItem(
                value: ScheduleClass.b,
                child: Text(s.pharmacyScheduleB),
              ),
              DropdownMenuItem(
                value: ScheduleClass.d,
                child: Text(s.pharmacyScheduleD),
              ),
              DropdownMenuItem(
                value: ScheduleClass.other,
                child: Text(s.pharmacyScheduleOther),
              ),
            ],
            onChanged: (value) {
              setState(() => _schedule = value);
              _changed();
            },
          ),
          if (_schedule != null) ...[
            const SizedBox(height: BlTokens.space1),
            Text(
              s.pharmacyScheduleNote,
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
