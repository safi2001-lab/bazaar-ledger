import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Where a loan's money came in or went out: the cash drawer, a bank, a
/// wallet. Never the cheque drawer: Cheques in Hand is paper customers gave
/// the shop, and the writer refuses it too.
class MoneyAccountChips extends ConsumerWidget {
  const MoneyAccountChips({
    required this.label,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final String label;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// The accounts on offer, and which one is picked until the shopkeeper
  /// picks another.
  static (List<PaymentAccountSummary>, String?) resolve(
    List<PaymentAccountSummary> all,
    String? picked,
  ) {
    final offered = [
      for (final a in all)
        if (a.modeLabel != 'cheque') a,
    ];
    final id =
        picked ??
        (offered.isEmpty
            ? null
            : offered
                  .firstWhere((a) => a.isDefault, orElse: () => offered.first)
                  .id);
    return (offered, id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bl;
    final (offered, id) = resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      selectedId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: t.inkMuted)),
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final a in offered)
              ChoiceChip(
                selected: a.id == id,
                label: Text(a.name),
                onSelected: (_) => onSelected(a.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// The day a loan was taken or paid, today unless changed. Never a day not
/// yet come: the writer refuses one, so the picker does not offer it.
class LoanDateField extends StatelessWidget {
  const LoanDateField({
    required this.date,
    required this.today,
    required this.onChanged,
    super.key,
  });

  final BusinessDate date;
  final BusinessDate today;
  final ValueChanged<BusinessDate> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          s.loanDate(date.value),
          style: TextStyle(fontSize: 15, color: t.ink),
        ),
        ActionChip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(s.loanPickDate),
          onPressed: () async {
            final last = DateTime.utc(today.year, today.month, today.day);
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.utc(date.year, date.month, date.day),
              firstDate: DateTime.utc(today.year - 10),
              lastDate: last,
            );
            if (picked == null) return;
            onChanged(
              BusinessDate(
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
              ),
            );
          },
        ),
      ],
    );
  }
}

/// An amount typed into a field: nothing when empty, null when it is not an
/// amount at all.
Money? typedMoney(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return Money.zero;
  return Money.tryParse(raw);
}

/// A yearly rate typed as a percentage, `16.5`, as basis points: 1650.
/// Null when nothing was typed, and -1 when what was typed is not a rate,
/// which the writer then refuses in words. Read through [Money.tryParse],
/// which holds two places exactly, so no rate passes through a float.
int? typedRateBp(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  final parsed = Money.tryParse(raw);
  if (parsed == null || parsed.isNegative) return -1;
  return parsed.inPaisa;
}
