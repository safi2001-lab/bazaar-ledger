import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'advance_screen.dart';
import 'employee_editor_screen.dart';
import 'salary_screen.dart';
import 'slip_screen.dart';
import 'staff_providers.dart';

/// One man's page in the staff book (M65): who he is and what he is paid,
/// the month's register as a grid, his wages as they stand, what he owes of
/// his advances, and every slip he was paid on.
class EmployeeScreen extends ConsumerStatefulWidget {
  const EmployeeScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends ConsumerState<EmployeeScreen> {
  SalaryMonth? _month;

  Future<void> _cancelAdvance(AdvanceLine line) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await askReason(context, s.staffAdvanceCancelTitle);
    if (reason == null) return;
    try {
      final no = await ref
          .read(appServicesProvider)
          .staffBook
          .cancelAdvance(
            employeeId: widget.employeeId,
            entryId: line.entryId,
            reason: reason,
          );
      ref.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.staffAdvanceCancelled(no))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(staffError(s, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final today = BusinessDate.now(services.clock);
    final man = ref.watch(employeeProvider(widget.employeeId)).valueOrNull;
    final month = _month ?? SalaryMonth.of(today);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(man?.name ?? s.staffBookTitle),
        actions: [
          if (man != null && services.staffBook.mayKeep)
            BlIconButton(
              icon: Icons.edit_outlined,
              label: s.staffEdit,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EmployeeEditorScreen(existing: man),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: man == null
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space4,
                  BlTokens.space4,
                  BlTokens.space10,
                ),
                children: [
                  _Header(man: man),
                  const SizedBox(height: BlTokens.space3),
                  _AdvanceCard(man: man),
                  const SizedBox(height: BlTokens.space4),
                  _MonthCard(
                    man: man,
                    month: month,
                    today: today,
                    onMonth: (m) => setState(() => _month = m),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  _Slips(employeeId: man.id),
                  _AdvanceLedger(
                    employeeId: man.id,
                    onCancel: (line) => unawaited(_cancelAdvance(line)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Asks why something is being cancelled; null when the shopkeeper backs
/// out or gives no reason.
Future<String?> askReason(BuildContext context, String title) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title),
  );
  return reason == null || reason.isEmpty ? null : reason;
}

/// Owns its field, so the field outlives the dialog's closing animation.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _reason,
        autofocus: true,
        decoration: InputDecoration(labelText: s.staffCancelReason),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionBack),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(s.staffCancelConfirm),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.man});

  final Employee man;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    TextStyle muted() => TextStyle(fontSize: 13, color: t.inkMuted);
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${kaamName(s, man.kaam)} · ${payText(s, man.basis, man.rate)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
          Text(s.staffJoinedOn(man.joinedOn.value), style: muted()),
          if (man.leftOn != null)
            Text(s.staffLeftOn(man.leftOn!.value), style: muted()),
          if (man.phone != null) Text(man.phone!, style: muted()),
          if (man.cnic != null)
            Text(s.staffCnicShown(cnicDisplay(man.cnic!)), style: muted()),
          if (man.userName != null)
            Text(s.staffSignsInAs(man.userName!), style: muted()),
        ],
      ),
    );
  }
}

class _AdvanceCard extends ConsumerWidget {
  const _AdvanceCard({required this.man});

  final Employee man;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final lines = ref.watch(advanceLinesProvider(man.id)).valueOrNull;
    final owed = lines == null || lines.isEmpty
        ? Money.zero
        : lines.last.owedAfter;
    return BlCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.staffAdvanceOwed,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
                BlMoney(owed, size: 18, withSymbol: true),
              ],
            ),
          ),
          BlButton(
            label: s.staffGiveAdvance,
            icon: Icons.payments_outlined,
            kind: BlButtonKind.secondary,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AdvanceScreen(employee: man),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends ConsumerWidget {
  const _MonthCard({
    required this.man,
    required this.month,
    required this.today,
    required this.onMonth,
  });

  final Employee man;
  final SalaryMonth month;
  final BusinessDate today;
  final ValueChanged<SalaryMonth> onMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final thisMonth = SalaryMonth.of(today);
    final data = ref
        .watch(employeeMonthProvider((id: man.id, month: month.code)))
        .valueOrNull;
    final w = data?.working;
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BlIconButton(
                icon: Icons.chevron_left,
                label: s.staffMonthBefore,
                onPressed: () => onMonth(month.previous),
              ),
              Expanded(
                child: Text(
                  monthLabel(month),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              BlIconButton(
                icon: Icons.chevron_right,
                label: s.staffMonthAfter,
                onPressed: month == thisMonth
                    ? null
                    : () => onMonth(month.next),
              ),
            ],
          ),
          if (data != null) ...[
            _MonthGrid(month: month, marks: data.marks, man: man),
            const SizedBox(height: BlTokens.space2),
            if (w != null) ...[
              Text(
                tallyText(s, w.tally),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.staffMonthWages(w.paidDaysText),
                      style: TextStyle(fontSize: 15, color: t.ink),
                    ),
                  ),
                  BlMoney(w.basePay, size: 17, withSymbol: true),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              if (data.paidSlipNo case final no?)
                BlChip(s.staffMonthPaid(no), tone: BlChipTone.good)
              else if (w.tally.employedDays > 0)
                BlButton(
                  label: s.staffPayMonth(monthLabel(month)),
                  icon: Icons.account_balance_wallet_outlined,
                  expand: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SalaryScreen(employee: man, month: month),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// "Haazir 20 · Late 1 · Aadha din 1 · Ghair haazir 2 · Nishan nahi 6".
String tallyText(AppStrings s, MonthTally t) => [
  '${s.staffMarkPresent} ${t.present}',
  if (t.late > 0) '${s.staffMarkLate} ${t.late}',
  if (t.halfDay > 0) '${s.staffMarkHalfDay} ${t.halfDay}',
  if (t.paidLeave > 0) '${s.staffMarkPaidLeave} ${t.paidLeave}',
  if (t.unpaidLeave > 0) '${s.staffMarkUnpaidLeave} ${t.unpaidLeave}',
  if (t.absent > 0) '${s.staffMarkAbsent} ${t.absent}',
  if (t.unmarked > 0) '${s.staffNotMarkedCount} ${t.unmarked}',
].join(' · ');

/// The month as a grid of its days, each with its mark.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.marks,
    required this.man,
  });

  final SalaryMonth month;
  final Map<String, AttendanceMark> marks;
  final Employee man;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final days = month.everyDay;
    // Monday first, as a Pakistani wall calendar is.
    final lead = DateTime.utc(month.year, month.month).weekday - 1;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final day in days)
        _DayCell(
          key: ValueKey('day-${day.value}'),
          day: day.day,
          mark: marks[day.value],
          onPayroll: man.worksOn(day),
          short: switch (marks[day.value]) {
            final m? => markShort(s, m),
            null => '',
          },
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final side = (box.maxWidth - 6 * BlTokens.space1) ~/ 7;
        return Wrap(
          spacing: BlTokens.space1,
          runSpacing: BlTokens.space1,
          children: [
            for (final c in cells)
              SizedBox(
                width: side.toDouble(),
                height: side.toDouble() < 36 ? 36 : side.toDouble(),
                child: c,
              ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.mark,
    required this.onPayroll,
    required this.short,
  });

  final int day;
  final AttendanceMark? mark;
  final bool onPayroll;
  final String short;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final colour = switch (mark) {
      AttendanceMark.absent || AttendanceMark.unpaidLeave => t.danger,
      AttendanceMark.halfDay || AttendanceMark.late => t.warning,
      AttendanceMark.present || AttendanceMark.paidLeave => t.money,
      null => t.inkFaint,
    };
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BlTokens.radiusSm),
        border: Border.all(color: onPayroll ? t.line : t.paper),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 11,
                  color: onPayroll ? t.inkMuted : t.inkFaint,
                ),
              ),
              Text(
                short,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slips extends ConsumerWidget {
  const _Slips({required this.employeeId});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final slips = ref.watch(slipsProvider(employeeId)).valueOrNull ?? const [];
    if (slips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlSectionHeader(s.staffSlips),
        for (final slip in slips)
          Padding(
            padding: const EdgeInsets.only(bottom: BlTokens.space2),
            child: BlCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SlipScreen(slipId: slip.id),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monthLabel(slip.month),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: slip.cancelled ? t.inkMuted : t.ink,
                          ),
                        ),
                        Text(
                          '${slip.slipNo} · ${slip.paidOn.value}',
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                        if (slip.cancelled)
                          BlChip(s.staffSlipCancelled, tone: BlChipTone.bad),
                      ],
                    ),
                  ),
                  BlMoney(slip.figures.net, size: 16),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdvanceLedger extends ConsumerWidget {
  const _AdvanceLedger({required this.employeeId, required this.onCancel});

  final String employeeId;
  final ValueChanged<AdvanceLine> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final lines =
        ref.watch(advanceLinesProvider(employeeId)).valueOrNull ?? const [];
    if (lines.isEmpty) return const SizedBox.shrink();
    String kind(AdvanceLineKind k) => switch (k) {
      AdvanceLineKind.given => s.staffAdvanceGiven,
      AdvanceLineKind.recovered => s.staffAdvanceRecovered,
      AdvanceLineKind.givenCancelled => s.staffAdvanceGivenCancelled,
      AdvanceLineKind.recoveryCancelled => s.staffAdvanceRecoveryCancelled,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlSectionHeader(s.staffAdvances),
        for (final line in lines.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: BlTokens.space2),
            child: BlCard(
              padding: const EdgeInsets.all(BlTokens.space3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kind(line.kind),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: line.cancelled ? t.inkMuted : t.ink,
                          ),
                        ),
                        Text(
                          '${line.entryNo} · ${line.on.value}',
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                        Text(
                          s.staffAdvanceOwedAfter(line.owedAfter.amountOnly),
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  BlMoney(
                    line.kind == AdvanceLineKind.given ||
                            line.kind == AdvanceLineKind.recoveryCancelled
                        ? line.amount
                        : -line.amount,
                    size: 15,
                    showSign: true,
                  ),
                  if (line.kind == AdvanceLineKind.given && !line.cancelled)
                    BlIconButton(
                      icon: Icons.undo,
                      label: s.staffAdvanceCancelTitle,
                      onPressed: () => onCancel(line),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
