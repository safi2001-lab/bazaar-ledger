import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../subscription/plans_screen.dart';
import 'loan_fields.dart';

/// Writing down a loan the shop has taken (M48): who lent it, how much,
/// where the money came in, and the terms if there are any.
///
/// Only the lender and the amount are asked for. A committee or a brother
/// lends with no rate, no term and no instalment, and a form that demanded
/// them would be filled with zeros nobody meant. The rate, when there is
/// one, only decides the interest the repayment screen suggests.
class TakeLoanScreen extends ConsumerStatefulWidget {
  const TakeLoanScreen({super.key});

  @override
  ConsumerState<TakeLoanScreen> createState() => _TakeLoanScreenState();
}

class _TakeLoanScreenState extends ConsumerState<TakeLoanScreen> {
  final _lender = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _instalment = TextEditingController();
  final _fee = TextEditingController();
  final _notes = TextEditingController();

  String? _into;
  BusinessDate? _date;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    for (final c in [
      _lender,
      _amount,
      _rate,
      _term,
      _instalment,
      _fee,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String? into, BusinessDate date) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount = typedMoney(_amount.text);
    final fee = typedMoney(_fee.text);
    final instalment = typedMoney(_instalment.text);
    final term = _term.text.trim();
    if (amount == null || fee == null || instalment == null || into == null) {
      setState(() => _failure = s.loanAmountInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(appServicesProvider)
          .loans
          .take(
            LoanDraft(
              lender: _lender.text,
              amount: amount,
              fee: fee,
              intoPaymentAccountId: into,
              takenOn: date,
              rateBp: typedRateBp(_rate.text),
              termMonths: term.isEmpty ? null : (int.tryParse(term) ?? -1),
              instalment: instalment.isZero ? null : instalment,
              notes: _notes.text,
            ),
          );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.loanSaved)));
      navigator.pop();
    } on PlanRequired catch (refused) {
      if (!mounted) return;
      setState(() => _busy = false);
      await offerPlan(context, refused);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          LoanRefused(:final reason) => reason,
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
    final services = ref.watch(appServicesProvider);
    final today = BusinessDate.now(services.clock);
    final date = _date ?? today;
    final (_, into) = MoneyAccountChips.resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      _into,
    );
    final amount = typedMoney(_amount.text) ?? Money.zero;
    final fee = typedMoney(_fee.text) ?? Money.zero;

    void changed(String _) => setState(() => _failure = null);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.loansNew)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space5,
                ),
                children: [
                  BlField(
                    controller: _lender,
                    label: s.loanLender,
                    autofocus: true,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _amount,
                    label: s.loanAmount,
                    numeric: true,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space4),
                  MoneyAccountChips(
                    label: s.loanInto,
                    selectedId: into,
                    onSelected: (id) => setState(() => _into = id),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  LoanDateField(
                    date: date,
                    today: today,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  BlField(
                    controller: _rate,
                    label: s.loanRate,
                    numeric: true,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _term,
                    label: s.loanTerm,
                    numeric: true,
                    decimals: 0,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _instalment,
                    label: s.loanInstalment,
                    numeric: true,
                    onChanged: changed,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _fee,
                    label: s.loanFee,
                    numeric: true,
                    onChanged: changed,
                  ),
                  if (fee.isPositive && amount > fee) ...[
                    const SizedBox(height: BlTokens.space1),
                    Text(
                      s.loanReceivedAfterFee((amount - fee).amountOnly),
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ],
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _notes,
                    label: s.loanNotes,
                    maxLines: 2,
                    onChanged: changed,
                  ),
                ],
              ),
            ),
            // Pinned, as on the expense screen: whatever the keyboard
            // squeezes out, Save stays reachable.
            Container(
              width: double.infinity,
              color: t.surface,
              padding: EdgeInsets.only(
                left: BlTokens.space4,
                right: BlTokens.space4,
                top: BlTokens.space3,
                bottom:
                    BlTokens.space3 +
                    (MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 0
                        : MediaQuery.viewPaddingOf(context).bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null) ...[
                    Text(
                      _failure!,
                      style: TextStyle(color: t.danger, fontSize: 14),
                    ),
                    const SizedBox(height: BlTokens.space2),
                  ],
                  BlButton(
                    label: s.loanSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_save(into, date)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
