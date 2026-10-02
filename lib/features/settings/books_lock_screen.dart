import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/history_screen.dart';

final _locksProvider =
    FutureProvider.autoDispose<
      ({BookLocks locks, BusinessDate suggested, List<LateArrival> late})
    >((ref) async {
      ref.watch(refreshTickProvider);
      final audit = ref.watch(appServicesProvider).audit;
      return (
        locks: await audit.locks(),
        suggested: await audit.suggestedCloseDate(),
        late: await audit.lateArrivals(),
      );
    });

/// The owner's two locks (M42): the books closed up to a day, and a PIN
/// before anything is undone.
///
/// The day offered first is the last one counted at the drawer, because
/// that is the day the owner already treats as done: the cash was counted
/// against it and the difference written down. A month's end is the other
/// natural line, for the shop whose accountant takes the books monthly; any
/// day can be picked. Closing is undone here too, and that act is itself
/// one Data Lock asks a PIN for.
///
/// Below them, anything a counter sent in after the books were closed —
/// taken in, since that counter did not know, and listed here so the owner
/// can look at the closed figures again with it.
class BooksLockScreen extends ConsumerStatefulWidget {
  const BooksLockScreen({super.key});

  @override
  ConsumerState<BooksLockScreen> createState() => _BooksLockScreenState();
}

class _BooksLockScreenState extends ConsumerState<BooksLockScreen> {
  bool _busy = false;
  String? _failure;

  Future<void> _do(Future<void> Function() act, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await act();
      if (!mounted) return;
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on PermissionDenied catch (denied) {
      if (mounted) setState(() => _failure = denied.reason);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(BusinessDate? through) {
    final s = AppStrings.of(context);
    final audit = ref.read(appServicesProvider).audit;
    return _do(
      () => audit.closeBooksThrough(through),
      through == null ? s.booksReopened : s.booksClosedDone(through.value),
    );
  }

  Future<void> _pick(BusinessDate suggested) async {
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    DateTime asDay(BusinessDate d) => DateTime(d.year, d.month, d.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: asDay(suggested),
      firstDate: DateTime(2000),
      lastDate: asDay(today),
    );
    if (picked == null || !mounted) return;
    final day = BusinessDate.tryParse(
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}',
    );
    if (day != null) await _close(day);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final state = ref.watch(_locksProvider);
    final hasPin = services.currentUser?.hasPin ?? false;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.booksLockTitle)),
      body: SafeArea(
        child: state.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
            ),
          ),
          data: (data) {
            final through = data.locks.closedThrough;
            final suggested = data.suggested;
            return ListView(
              padding: const EdgeInsets.all(BlTokens.space4),
              children: [
                BlCard(
                  accent: through != null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            through == null
                                ? Icons.lock_open_outlined
                                : Icons.lock_clock_outlined,
                            color: through == null ? t.inkMuted : t.accent,
                          ),
                          const SizedBox(width: BlTokens.space3),
                          Expanded(
                            child: Text(
                              through == null
                                  ? s.booksOpenNow
                                  : s.booksClosedThrough(through.value),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BlTokens.space2),
                      Text(
                        s.booksCloseExplain,
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                      const SizedBox(height: BlTokens.space3),
                      if (through?.value != suggested.value) ...[
                        BlButton(
                          label: s.booksCloseThrough(suggested.value),
                          icon: Icons.lock_outline,
                          busy: _busy,
                          onPressed: _busy
                              ? null
                              : () => unawaited(_close(suggested)),
                        ),
                        const SizedBox(height: BlTokens.space2),
                      ],
                      BlButton(
                        label: s.booksClosePick,
                        icon: Icons.event_outlined,
                        kind: BlButtonKind.secondary,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_pick(through ?? suggested)),
                      ),
                      if (through != null) ...[
                        const SizedBox(height: BlTokens.space2),
                        BlButton(
                          label: s.booksReopen,
                          icon: Icons.lock_open_outlined,
                          kind: BlButtonKind.ghost,
                          onPressed: _busy
                              ? null
                              : () => unawaited(_close(null)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BlTokens.space3),
                BlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A row and a switch rather than a SwitchListTile, whose
                      // ink would be painted under the card and hidden by it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.dataLockTitle,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: t.ink,
                                  ),
                                ),
                                const SizedBox(height: BlTokens.space1),
                                Text(
                                  s.dataLockExplain,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: t.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: BlTokens.space2),
                          Switch(
                            value: data.locks.dataLock,
                            onChanged:
                                _busy || (!hasPin && !data.locks.dataLock)
                                ? null
                                : (on) => unawaited(
                                    _do(
                                      () => services.audit.setDataLock(on: on),
                                      s.dataLockTitle,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      if (!hasPin && !data.locks.dataLock)
                        Text(
                          s.dataLockNeedsPin,
                          style: TextStyle(fontSize: 13, color: t.warning),
                        ),
                    ],
                  ),
                ),
                if (_failure case final failure?) ...[
                  const SizedBox(height: BlTokens.space3),
                  Text(failure, style: TextStyle(color: t.danger)),
                ],
                if (data.late.isNotEmpty) ...[
                  BlSectionHeader(s.lateArrivalsTitle),
                  Text(
                    s.lateArrivalsExplain,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  for (final a in data.late)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: BlCard(
                        onTap: RecordRef.supports(a.record.table)
                            ? () => unawaited(
                                openHistory(
                                  context,
                                  record: a.record,
                                  label: a.number,
                                ),
                              )
                            : null,
                        child: Row(
                          children: [
                            Icon(Icons.sync_problem_outlined, color: t.warning),
                            const SizedBox(width: BlTokens.space3),
                            Expanded(
                              child: Text(
                                '${a.number} · ${a.dateLocal} · ${a.device}',
                                style: TextStyle(fontSize: 14, color: t.ink),
                              ),
                            ),
                            if (a.amount case final amount?)
                              BlMoney(amount, size: 14),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
