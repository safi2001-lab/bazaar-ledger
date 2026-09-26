import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What a cheque says: its number, its bank, and the day it can be banked.
///
/// Shared by the counter and the khata, because a cheque is the same piece of
/// paper whichever screen it is handed over at. The due date is the part
/// that makes it post-dated: wholesale goods go out on the 1st against a
/// cheque dated the 30th, and without the date the shop cannot know when to
/// bank it or when it is late.
///
/// The common terms are one tap — today, fifteen, thirty, forty-five and
/// sixty days — because that is how the trade writes them; any other day is
/// a picker away.
class ChequeFields extends StatelessWidget {
  const ChequeFields({
    super.key,
    required this.number,
    this.bank,
    required this.today,
    required this.due,
    required this.onDueChanged,
    this.onChanged,
  });

  final TextEditingController number;

  /// Null for a cheque the shop writes itself: the bank is the account it
  /// is drawn on, already chosen.
  final TextEditingController? bank;

  /// The shop's business date now. Due dates are offered relative to it.
  final BusinessDate today;
  final BusinessDate due;
  final ValueChanged<BusinessDate> onDueChanged;
  final VoidCallback? onChanged;

  static const _terms = [0, 15, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final inDays = daysUntil(today, due);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlField(
          controller: number,
          label: s.wasooliChequeNo,
          onChanged: (_) => onChanged?.call(),
        ),
        if (bank case final bank?) ...[
          const SizedBox(height: BlTokens.space2),
          BlField(controller: bank, label: s.wasooliChequeBank),
        ],
        const SizedBox(height: BlTokens.space3),
        Text(s.chequeDue, style: TextStyle(fontSize: 13, color: t.inkMuted)),
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final days in _terms)
              ChoiceChip(
                selected: inDays == days,
                label: Text(
                  days == 0 ? s.chequeDueToday : s.chequeDueInDays('$days'),
                ),
                onSelected: (_) => onDueChanged(today.addDays(days)),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(s.chequeDuePick),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.utc(due.year, due.month, due.day),
                  // A cheque is valid for six months from its date in
                  // Pakistan; one dated further back cannot be banked.
                  firstDate: DateTime.utc(
                    today.year,
                    today.month,
                    today.day,
                  ).subtract(const Duration(days: 180)),
                  lastDate: DateTime.utc(
                    today.year,
                    today.month,
                    today.day,
                  ).add(const Duration(days: 365)),
                );
                if (picked != null) {
                  onDueChanged(
                    BusinessDate(
                      '${picked.year.toString().padLeft(4, '0')}-'
                      '${picked.month.toString().padLeft(2, '0')}-'
                      '${picked.day.toString().padLeft(2, '0')}',
                    ),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: BlTokens.space1),
        Text(
          s.chequeDueOn(due.value),
          style: TextStyle(fontSize: 13, color: t.ink),
        ),
      ],
    );
  }
}
