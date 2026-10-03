import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'recurring_bill_screen.dart';
import 'recurring_list_screen.dart';
import 'recurring_providers.dart';

/// "Har hafte / Har mahine banayein" from a posted bill (M63): the receipt's
/// dots, or the sales list's send sheet.
///
/// Opens the repeating bill's set-up with the bill's customer and goods
/// already in it — every week on today's weekday from tomorrow, at the day's
/// prices, only reminding — for the shopkeeper to change and save. A
/// walk-in's bill is refused in words: a repeating bill goes on a khata.
Future<void> startRepeatFromBill(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
}) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final services = ref.read(appServicesProvider);
  try {
    final start = await services.recurring.startFromBill(documentId);
    unawaited(
      navigator.push(
        MaterialPageRoute<bool>(
          builder: (_) => RecurringBillScreen(
            bill: start.bill,
            isNew: true,
            leftOut: recurringLeftOutText(s, start.leftOut),
          ),
        ),
      ),
    );
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(recurringProblemText(s, error))),
    );
  }
}

/// A customer's repeating bills on their khata (M63), and a way to start
/// one: from their last bill when they have one, or empty to fill in.
///
/// Nothing at all for a role that may not sell.
class RecurringOnKhata extends ConsumerWidget {
  const RecurringOnKhata({super.key, required this.partyId});

  final String partyId;

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final services = ref.read(appServicesProvider);
    try {
      final start = await services.recurring.startForParty(partyId);
      unawaited(
        navigator.push(
          MaterialPageRoute<bool>(
            builder: (_) => RecurringBillScreen(
              bill: start.bill,
              isNew: true,
              leftOut: recurringLeftOutText(s, start.leftOut),
            ),
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(recurringProblemText(s, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final services = ref.watch(appServicesProvider);
    if (!services.recurring.mayUse) return const SizedBox.shrink();
    final bills = ref.watch(recurringForPartyProvider(partyId)).valueOrNull;
    final today = services.recurring.today;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bills != null && bills.isNotEmpty) ...[
            BlSectionHeader(s.recurringOnKhata),
            const SizedBox(height: BlTokens.space2),
            for (final b in bills) RecurringBillTile(bill: b, today: today),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: BlButton(
              label: s.recurringNewForParty,
              icon: Icons.event_repeat_outlined,
              kind: BlButtonKind.ghost,
              onPressed: () => unawaited(_start(context, ref)),
            ),
          ),
        ],
      ),
    );
  }
}
