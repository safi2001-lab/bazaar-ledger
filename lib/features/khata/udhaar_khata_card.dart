import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'chase_screen.dart';

/// What the card shows: how much is out, how much of it is late, and with
/// how many customers.
///
/// Its own read rather than a watch on the udhaar list's providers. Home is
/// always on screen, so watching those would keep them alive for the whole
/// session and the udhaar list would open on whatever they last read,
/// instead of reading afresh as every other screen does.
final _udhaarKhataProvider =
    FutureProvider.autoDispose<({DueAging aging, int owing})>((ref) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return (aging: const DueAging({}), owing: 0);
      final today = services.udhaar.today;
      final aging = await services.udhaar.queries.dueAging(
        firm.id,
        asOfDateLocal: today,
      );
      final owing = await services.udhaar.queries.dueParties(
        firm.id,
        asOfDateLocal: today,
      );
      return (aging: aging, owing: owing.length);
    });

/// The udhaar khata, named as the shopkeeper names it, on the first screen
/// (M64).
///
/// Everything a khata does was already built — what each customer owes, the
/// bills and the history, taking a payment, the reminders, the promises —
/// but it was reached through a tile called "Gahak", and the owner trying
/// the app asked where the udhaar khata was. A shopkeeper looks for the
/// book by its name, so the book has its name on the front, with the one
/// figure that matters in it: how much is out, and with how many people.
///
/// It opens the udhaar list (the chase list): everyone who owes, the total,
/// how late each is, and the reminders; each name opens their own khata.
/// Shown even when nobody owes anything, because "where is the khata" is
/// asked on the first day too.
class UdhaarKhataCard extends ConsumerWidget {
  const UdhaarKhataCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final figures = ref.watch(_udhaarKhataProvider).valueOrNull;
    final total = figures?.aging.total;
    final late = figures?.aging.overdue;

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: BlCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ChaseScreen()),
        ),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 28, color: t.warning),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.homeUdhaarKhata,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: BlTokens.space1),
                  Text(
                    total == null || !total.isPositive
                        ? s.homeUdhaarKhataClear
                        : s.homeUdhaarKhataOwed(figures?.owing ?? 0),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (late != null && late.isPositive)
                    Text(
                      s.homeUdhaarKhataLate(late.amountOnly),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.danger),
                    ),
                ],
              ),
            ),
            if (total != null && total.isPositive) ...[
              const SizedBox(width: BlTokens.space2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: BlMoney(
                    total,
                    size: 20,
                    withSymbol: true,
                    semanticPrefix: s.homeUdhaarKhata,
                  ),
                ),
              ),
            ],
            Icon(Icons.chevron_right, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}
