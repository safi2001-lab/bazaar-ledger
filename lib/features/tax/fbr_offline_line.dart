import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'fbr_screen.dart';

/// The FBR queue's bills issued in offline mode, and those past Rule
/// 150XC's 24 hours (M59).
final fbrOfflineWatchProvider = FutureProvider.autoDispose<FbrOfflineWatch>((
  ref,
) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).fbr.offlineWatch();
});

/// One small line on Home when a bill made offline is still not with FBR a
/// day after the connection came back (Rule 150XC). Nothing at all the rest
/// of the time, and nothing for a shop that does not report: Home is for
/// the day's numbers, and this earns its place only when it is late.
class FbrOverdueLine extends ConsumerWidget {
  const FbrOverdueLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue =
        ref.watch(fbrOfflineWatchProvider).valueOrNull?.overdue ?? const [];
    if (overdue.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: InkWell(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const FbrScreen())),
        child: Container(
          padding: const EdgeInsets.all(BlTokens.space3),
          decoration: BoxDecoration(
            color: t.dangerSurface,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: t.danger),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  s.homeFbrOverdue(overdue.length),
                  style: TextStyle(fontSize: 13, color: t.danger),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.danger),
            ],
          ),
        ),
      ),
    );
  }
}

/// On the FBR screen, above the bills: how many were issued offline and are
/// waiting, and how many of those are past the 24 hours.
class FbrOfflineSummary extends ConsumerWidget {
  const FbrOfflineSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(fbrOfflineWatchProvider).valueOrNull;
    if (watch == null || watch.offline == 0) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    final late = watch.overdue.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: BlTokens.space2),
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: late ? t.dangerSurface : t.warningSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.fbrOfflineSummary(watch.offline),
            style: TextStyle(fontSize: 13, color: t.warning),
          ),
          if (late)
            Text(
              s.fbrOverdueSummary(watch.overdue.length),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.danger,
              ),
            ),
        ],
      ),
    );
  }
}
