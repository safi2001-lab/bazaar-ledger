import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../loans/loan_fields.dart';
import 'employee_screen.dart' show tallyText;
import 'slip_screen.dart';
import 'staff_providers.dart';

final _owedProvider = FutureProvider.autoDispose.family<Money, String>((
  ref,
  id,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).staffBook.advanceOwed(id);
});

/// A month's wages, worked out from the register and paid (M65).
///
/// The register and the shop's rule give the base pay, and the screen says
/// how: the days paid for, the days cut, and the days nobody marked (worked,
/// for a monthly man; not worked, for a daily one). The shopkeeper adds a
/// bonus or overtime and takes off a cut, chooses how much of the advance
/// comes back this month — all of it that the month will bear, unless he
/// says otherwise — and the rest is put in the man's hand. The same screen
/// puts a slip right: the old one cancelled and this one paid in one act.
class SalaryScreen extends ConsumerStatefulWidget {
  const SalaryScreen({
    super.key,
    required this.employee,
    required this.month,
    this.replacing,
  });

  final Employee employee;
  final SalaryMonth month;

  /// The slip this one corrects, when it does.
  final SalarySlip? replacing;

  @override
  ConsumerState<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends ConsumerState<SalaryScreen> {
  final List<SalaryLine> _lines = [];
  final _label = TextEditingController();
  final _lineAmount = TextEditingController();
  final _recover = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  SalaryLineKind _kind = SalaryLineKind.bonus;
  bool _recoverTouched = false;

  /// What comes back off the advance until the shopkeeper types otherwise,
  /// as the last frame worked it out.
  Money _suggested = Money.zero;
  String? _from;
  BusinessDate? _date;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final old = widget.replacing;
    if (old != null) {
      _lines.addAll(old.lines);
      _recover.text = old.figures.recovered.amountOnly.replaceAll(',', '');
      _recoverTouched = true;
      _from = old.paymentAccountId;
      _note.text = old.note ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_label, _lineAmount, _recover, _note, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    final s = AppStrings.of(context);
    final amount = typedMoney(_lineAmount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _failure = s.staffAmountInvalid);
      return;
    }
    final label = _label.text.trim();
    setState(() {
      _lines.add(
        SalaryLine(
          kind: _kind,
          label: label.isEmpty ? _kindName(s, _kind) : label,
          amount: amount,
        ),
      );
      _label.clear();
      _lineAmount.clear();
      _failure = null;
    });
  }

  Future<void> _save(String? from, BusinessDate date) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final recovered = _recoverTouched ? typedMoney(_recover.text) : _suggested;
    if (recovered == null) {
      setState(() => _failure = s.staffAmountInvalid);
      return;
    }
    final old = widget.replacing;
    if (old != null && _reason.text.trim().isEmpty) {
      setState(() => _failure = s.staffCorrectReasonNeeded);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final draft = SalaryDraft(
      employeeId: widget.employee.id,
      month: widget.month,
      paidOn: date,
      lines: List.of(_lines),
      advanceRecovered: recovered,
      paymentAccountId: from,
      note: _note.text,
    );
    try {
      final book = ref.read(appServicesProvider).staffBook;
      final slipId = old == null
          ? await book.paySalary(draft)
          : await book.correctSalary(
              old.id,
              draft,
              reason: _reason.text.trim(),
            );
      ref.bumpRefresh();
      await navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => SlipScreen(slipId: slipId)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = staffError(s, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final date = _date ?? today;
    final man = widget.employee;
    final data = ref
        .watch(employeeMonthProvider((id: man.id, month: widget.month.code)))
        .valueOrNull;
    final owedNow = ref.watch(_owedProvider(man.id)).valueOrNull;
    final (_, from) = MoneyAccountChips.resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      _from,
    );
    final w = data?.working;
    if (w == null || owedNow == null) {
      return Scaffold(
        backgroundColor: t.paper,
        appBar: AppBar(title: Text(man.name)),
        body: const Padding(
          padding: EdgeInsets.all(BlTokens.space4),
          child: BlSkeletonList(rows: 4),
        ),
      );
    }
    // What a slip being corrected took back comes back to him first.
    final owed = owedNow + (widget.replacing?.figures.recovered ?? Money.zero);
    final additions = Money.sum([
      for (final l in _lines)
        if (l.kind.adds) l.amount,
    ]);
    final deductions = Money.sum([
      for (final l in _lines)
        if (!l.kind.adds) l.amount,
    ]);
    final earned = w.basePay + additions - deductions;
    // All of the advance the month will bear comes back, until the
    // shopkeeper says otherwise; written into the field after this frame,
    // since a field is not changed while it is being built.
    final suggested = earned < owed ? earned : owed;
    _suggested = suggested.isPositive ? suggested : Money.zero;
    final recovered = _recoverTouched
        ? (typedMoney(_recover.text) ?? Money.zero)
        : _suggested;
    if (!_recoverTouched) {
      final text = recovered.isPositive ? recovered.amountOnly : '';
      final plain = text.replaceAll(',', '');
      if (_recover.text != plain) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_recoverTouched) _recover.text = plain;
        });
      }
    }
    final net = earned - recovered;

    final rule = switch ((w.basis, w.dayRule)) {
      (PayBasis.daily, _) => s.staffRuleDaily(w.rate.amountOnly),
      (PayBasis.monthly, DayRule.calendar) => s.staffRuleCalendar(
        w.rate.amountOnly,
        w.basisDays,
      ),
      (PayBasis.monthly, _) => s.staffRuleThirty(w.rate.amountOnly),
    };

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(
          widget.replacing == null
              ? s.staffSalaryTitle(man.name, monthLabel(widget.month))
              : s.staffCorrectTitle(widget.replacing!.slipNo),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            MediaQuery.viewInsetsOf(context).bottom + BlTokens.space8,
          ),
          children: [
            BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule, style: TextStyle(fontSize: 14, color: t.ink)),
                  const SizedBox(height: BlTokens.space1),
                  Text(
                    s.staffOnPayroll(w.tally.employedDays),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  Text(
                    tallyText(s, w.tally),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (w.tally.unmarked > 0 || w.tally.toCome > 0) ...[
                    const SizedBox(height: BlTokens.space1),
                    Text(
                      w.basis == PayBasis.monthly
                          ? s.staffUnmarkedPaid(
                              w.tally.unmarked + w.tally.toCome,
                            )
                          : s.staffUnmarkedUnpaid(
                              w.tally.unmarked + w.tally.toCome,
                            ),
                      style: TextStyle(fontSize: 13, color: t.warning),
                    ),
                  ],
                  const SizedBox(height: BlTokens.space2),
                  _AmountRow(
                    label: s.staffBasePay(w.paidDaysText),
                    amount: w.basePay,
                  ),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            BlSectionHeader(s.staffLines),
            for (final (i, line) in _lines.indexed)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_kindName(s, line.kind)}: ${line.label}',
                      style: TextStyle(fontSize: 14, color: t.ink),
                    ),
                  ),
                  BlMoney(
                    line.kind.adds ? line.amount : -line.amount,
                    size: 14,
                    showSign: true,
                  ),
                  BlIconButton(
                    icon: Icons.close,
                    label: s.staffLineRemove,
                    onPressed: () => setState(() => _lines.removeAt(i)),
                  ),
                ],
              ),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final k in SalaryLineKind.values)
                  ChoiceChip(
                    selected: _kind == k,
                    label: Text(_kindName(s, k)),
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: BlTokens.space2),
            BlField(controller: _label, label: s.staffLineLabel),
            const SizedBox(height: BlTokens.space2),
            BlField(
              controller: _lineAmount,
              label: s.staffLineAmount,
              numeric: true,
            ),
            const SizedBox(height: BlTokens.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: BlButton(
                label: s.staffLineAdd,
                icon: Icons.add,
                kind: BlButtonKind.secondary,
                onPressed: _addLine,
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            if (owed.isPositive) ...[
              Text(
                s.staffAdvanceOwedNow(owed.amountOnly),
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
              const SizedBox(height: BlTokens.space2),
              BlField(
                controller: _recover,
                label: s.staffRecover,
                numeric: true,
                onChanged: (_) => setState(() {
                  _recoverTouched = true;
                  _failure = null;
                }),
              ),
              const SizedBox(height: BlTokens.space3),
            ],
            BlCard(
              accent: true,
              child: Column(
                children: [
                  _AmountRow(
                    label: s.staffGross,
                    amount: w.basePay + additions,
                  ),
                  if (deductions.isPositive)
                    _AmountRow(label: s.staffDeductions, amount: -deductions),
                  if (recovered.isPositive)
                    _AmountRow(
                      label: s.staffRecoveredShort,
                      amount: -recovered,
                    ),
                  const Divider(),
                  _AmountRow(label: s.staffInHand, amount: net, strong: true),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            if (net.isPositive) ...[
              MoneyAccountChips(
                label: s.staffPaidFrom,
                selectedId: from,
                onSelected: (id) => setState(() => _from = id),
              ),
              const SizedBox(height: BlTokens.space3),
            ],
            LoanDateField(
              date: date,
              today: today,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _note, label: s.staffNote),
            if (widget.replacing != null) ...[
              const SizedBox(height: BlTokens.space3),
              BlField(controller: _reason, label: s.staffCorrectReason),
            ],
            const SizedBox(height: BlTokens.space4),
            if (_failure != null) ...[
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
              const SizedBox(height: BlTokens.space2),
            ],
            BlButton(
              label: widget.replacing == null
                  ? s.staffPaySave
                  : s.staffCorrectSave,
              icon: Icons.check,
              big: true,
              expand: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => unawaited(_save(net.isPositive ? from : null, date)),
            ),
          ],
        ),
      ),
    );
  }
}

String _kindName(AppStrings s, SalaryLineKind kind) => switch (kind) {
  SalaryLineKind.bonus => s.staffLineBonus,
  SalaryLineKind.overtime => s.staffLineOvertime,
  SalaryLineKind.deduction => s.staffLineDeduction,
};

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final Money amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 16 : 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: t.ink,
              ),
            ),
          ),
          BlMoney(amount, size: strong ? 18 : 14),
        ],
      ),
    );
  }
}
