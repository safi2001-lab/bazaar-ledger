import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'staff_providers.dart';

/// The day's register (M65): everybody on the payroll that day, one tap a
/// man.
///
/// Fast because it is done standing at the shutter at nine in the morning:
/// one screen, every man on it, six marks each a tap, and "the rest are
/// present" for the day nothing happened. Any past day the owner has not
/// closed can be put right from here; a closed one is refused beneath the
/// screen and the owner may let a change in with his PIN (M42).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  BusinessDate? _day;
  final Set<String> _busy = {};

  Future<void> _mark(
    BusinessDate day,
    RegisterLine line,
    AttendanceMark mark,
  ) async {
    final id = line.employee.id;
    if (_busy.contains(id) || line.mark == mark) return;
    setState(() => _busy.add(id));
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appServicesProvider).staffBook.mark(day, {id: mark});
      ref.bumpRefresh();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(staffError(s, error))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _restPresent(BusinessDate day) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref
          .read(appServicesProvider)
          .staffBook
          .markRestPresent(day);
      ref.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.staffRegisterRestMarked(n))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(staffError(s, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final day = _day ?? today;
    final register = ref.watch(registerProvider(day.value));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.staffRegisterTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BlIconButton(
                  icon: Icons.chevron_left,
                  label: s.staffDayBefore,
                  onPressed: () => setState(() => _day = day.addDays(-1)),
                ),
                Text(
                  day == today ? s.staffRegisterToday : day.value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                BlIconButton(
                  icon: Icons.chevron_right,
                  label: s.staffDayAfter,
                  onPressed: day == today
                      ? null
                      : () => setState(() => _day = day.addDays(1)),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(s.staffPickDay),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.utc(day.year, day.month, day.day),
                      firstDate: DateTime.utc(today.year - 2),
                      lastDate: DateTime.utc(
                        today.year,
                        today.month,
                        today.day,
                      ),
                    );
                    if (picked == null) return;
                    // The day picked, as the calendar shows it: never moved
                    // through a time zone.
                    setState(
                      () => _day = BusinessDate.fromUtc(
                        DateTime.utc(picked.year, picked.month, picked.day),
                        Duration.zero,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            ...register.when(
              loading: () => const [BlSkeletonList(rows: 3)],
              error: (error, _) => [
                BlError(
                  title: s.commonSomethingWentWrong,
                  message: staffError(s, error),
                ),
              ],
              data: (lines) => [
                if (lines.isEmpty)
                  BlEmpty(
                    icon: Icons.fact_check_outlined,
                    title: s.staffRegisterEmpty,
                  )
                else ...[
                  if (lines.any((l) => l.mark == null))
                    BlButton(
                      label: s.staffRegisterRestPresent,
                      icon: Icons.done_all,
                      kind: BlButtonKind.secondary,
                      expand: true,
                      onPressed: () => unawaited(_restPresent(day)),
                    ),
                  const SizedBox(height: BlTokens.space3),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: _RegisterRow(
                        line: line,
                        busy: _busy.contains(line.employee.id),
                        onMark: (mark) => unawaited(_mark(day, line, mark)),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow({
    required this.line,
    required this.busy,
    required this.onMark,
  });

  final RegisterLine line;
  final bool busy;
  final ValueChanged<AttendanceMark> onMark;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return BlCard(
      padding: const EdgeInsets.all(BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.employee.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          Text(
            line.mark == null
                ? s.staffRegisterNotMarked
                : s.staffRegisterMarkedBy(
                    markName(s, line.mark!),
                    line.markedBy ?? '',
                  ),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space1,
            children: [
              for (final mark in AttendanceMark.values)
                ChoiceChip(
                  key: ValueKey('mark-${line.employee.id}-${mark.code}'),
                  selected: line.mark == mark,
                  label: Text(markName(s, mark)),
                  onSelected: busy ? null : (_) => onMark(mark),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
