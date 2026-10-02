import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'khata_screen.dart';

/// What the shop let go, written off or forgiven to settle (M44).
final allowancesProvider = FutureProvider.autoDispose
    .family<List<AllowanceRow>, AllowanceKind>((ref, kind) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.udhaar.queries.allowances(firm.id, kind: kind);
    });

/// The bad debts, and the settlement discounts, newest first (M44).
///
/// Who, how much, why, who let it go and when — and which have since been
/// cancelled, struck through rather than dropped, because "we wrote Aslam
/// off and then he paid" is part of the story. The total counts only what
/// stands. The formal report belongs to the reports hub, which reads the
/// same query (`UdhaarQueries.allowances`).
class BadDebtsScreen extends ConsumerStatefulWidget {
  const BadDebtsScreen({super.key});

  @override
  ConsumerState<BadDebtsScreen> createState() => _BadDebtsScreenState();
}

class _BadDebtsScreenState extends ConsumerState<BadDebtsScreen> {
  AllowanceKind _kind = AllowanceKind.writeOff;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final rows = ref.watch(allowancesProvider(_kind));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.badDebtsTitle)),
      body: SafeArea(
        child: rows.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
            ),
          ),
          data: (list) {
            final standing = Money.sum([
              for (final r in list)
                if (!r.cancelled) r.amount,
            ]);
            return ListView(
              padding: const EdgeInsets.all(BlTokens.space4),
              children: [
                SegmentedButton<AllowanceKind>(
                  segments: [
                    ButtonSegment(
                      value: AllowanceKind.writeOff,
                      label: Text(s.badDebtsWrittenOff),
                    ),
                    ButtonSegment(
                      value: AllowanceKind.settlementDiscount,
                      label: Text(s.badDebtsDiscounts),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
                const SizedBox(height: BlTokens.space3),
                BlCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.allowanceTotal,
                          style: TextStyle(fontSize: 13, color: t.inkMuted),
                        ),
                      ),
                      BlMoney(standing, size: 22, withSymbol: true),
                    ],
                  ),
                ),
                const SizedBox(height: BlTokens.space3),
                if (list.isEmpty)
                  BlEmpty(
                    icon: Icons.check_circle_outline,
                    title: s.badDebtsEmpty,
                  ),
                for (final r in list) _Row(row: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row});

  final AllowanceRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        // Their khata, where the line is and where it is cancelled from.
        onTap: () async {
          final navigator = Navigator.of(context);
          final services = ref.read(appServicesProvider);
          final firm = await ref.read(firmProvider.future);
          if (firm == null) return;
          final party = await services.queries.partyById(firm.id, row.partyId);
          if (party == null) return;
          await navigator.push(
            MaterialPageRoute<void>(builder: (_) => KhataScreen(party: party)),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.partyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                      decoration: row.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    '${row.paymentNo} · ${row.dateLocal}',
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  Text(
                    row.reason,
                    style: TextStyle(fontSize: 13, color: t.ink),
                  ),
                  Text(
                    s.allowanceBy(row.byName),
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  if (row.cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space1),
                      child: BlChip(
                        s.entryCancelled,
                        tone: BlChipTone.bad,
                        icon: Icons.block,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            BlMoney(row.amount, size: 16),
          ],
        ),
      ),
    );
  }
}
