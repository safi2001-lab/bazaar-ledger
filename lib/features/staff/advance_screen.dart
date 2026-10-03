import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../loans/loan_fields.dart';
import 'staff_providers.dart';

/// Giving a man an advance against his wages (M65): peshgi, from the drawer
/// or the bank, today unless changed. It sits in Staff Advances until it
/// comes back off his salary.
class AdvanceScreen extends ConsumerStatefulWidget {
  const AdvanceScreen({super.key, required this.employee});

  final Employee employee;

  @override
  ConsumerState<AdvanceScreen> createState() => _AdvanceScreenState();
}

class _AdvanceScreenState extends ConsumerState<AdvanceScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _from;
  BusinessDate? _date;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String? from, BusinessDate date) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount = typedMoney(_amount.text);
    if (amount == null || !amount.isPositive || from == null) {
      setState(() => _failure = s.staffAmountInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final no = await ref
          .read(appServicesProvider)
          .staffBook
          .giveAdvance(
            AdvanceDraft(
              employeeId: widget.employee.id,
              amount: amount,
              paymentAccountId: from,
              givenOn: date,
              note: _note.text,
            ),
          );
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.staffAdvanceSaved(no))));
      navigator.pop();
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
    final (_, from) = MoneyAccountChips.resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      _from,
    );
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.staffAdvanceTitle(widget.employee.name))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlField(
              controller: _amount,
              label: s.staffAdvanceAmount,
              numeric: true,
              autofocus: true,
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: BlTokens.space4),
            MoneyAccountChips(
              label: s.staffPaidFrom,
              selectedId: from,
              onSelected: (id) => setState(() => _from = id),
            ),
            const SizedBox(height: BlTokens.space3),
            LoanDateField(
              date: date,
              today: today,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _note, label: s.staffNote),
            const SizedBox(height: BlTokens.space2),
            Text(
              s.staffAdvanceHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            if (_failure != null) ...[
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
              const SizedBox(height: BlTokens.space2),
            ],
            BlButton(
              label: s.staffGiveAdvance,
              icon: Icons.check,
              big: true,
              expand: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save(from, date)),
            ),
          ],
        ),
      ),
    );
  }
}
