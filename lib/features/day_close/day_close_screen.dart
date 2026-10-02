import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/when.dart';
import '../reports/report_screen.dart';

final _drawerProvider =
    FutureProvider.autoDispose<({Money expected, ActivityEntry? last})>((
      ref,
    ) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return (expected: Money.zero, last: null);
      return (
        expected: await services.queries.cashInDrawer(firm.id),
        last: await services.queries.lastDayClose(firm.id),
      );
    });

/// The evening count: what the books say is in the golak, what was counted,
/// and the difference put through the books where it can be seen.
class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final counted = Money.tryParse(_counted.text);
    if (counted == null || _busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      await services.closeDay(
        services.actorNow(),
        counted: counted,
        note: _note.text,
      );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.dayCloseDone)));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          DayCloseRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final drawer = ref.watch(_drawerProvider);
    final counted = Money.tryParse(_counted.text);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.dayCloseTitle)),
      body: SafeArea(
        child: drawer.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (d) {
            final short = counted == null ? null : d.expected - counted;
            return ListView(
              padding: const EdgeInsets.all(BlTokens.space4),
              children: [
                BlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.dayCloseExpected,
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                      const SizedBox(height: BlTokens.space1),
                      BlMoney(d.expected, size: 28, withSymbol: true),
                      if (d.last case final last?) ...[
                        const SizedBox(height: BlTokens.space2),
                        Text(
                          s.dayCloseLast(
                            shopTime(last.atUtcMillis),
                            last.userName,
                          ),
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BlTokens.space4),
                BlField(
                  controller: _counted,
                  label: s.dayCloseCounted,
                  numeric: true,
                  autofocus: true,
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (short != null) ...[
                  const SizedBox(height: BlTokens.space2),
                  BlChip(
                    short.isZero
                        ? s.dayCloseMatches
                        : short.isPositive
                        ? s.dayCloseShort(short.amountOnly)
                        : s.dayCloseOver((-short).amountOnly),
                    tone: short.isZero
                        ? BlChipTone.good
                        : short.isPositive
                        ? BlChipTone.bad
                        : BlChipTone.warn,
                  ),
                ],
                const SizedBox(height: BlTokens.space3),
                BlField(controller: _note, label: s.dayCloseNote),
                if (_error != null) ...[
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    _error!,
                    style: TextStyle(color: t.danger, fontSize: 14),
                  ),
                ],
                const SizedBox(height: BlTokens.space4),
                BlButton(
                  label: s.dayCloseSave,
                  icon: Icons.lock_clock_outlined,
                  big: true,
                  busy: _busy,
                  onPressed: _busy || counted == null
                      ? null
                      : () => unawaited(_close()),
                ),
                // The night's Z report (M35), one tap from the count.
                const SizedBox(height: BlTokens.space2),
                TextButton.icon(
                  icon: const Icon(Icons.summarize_outlined),
                  label: Text(s.dayCloseSummary),
                  onPressed: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ReportScreen(kind: ReportKind.dailySummary),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
