import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'loan_fields.dart';

/// Paying some of a loan back (M48): what went out, how much of it was
/// interest and charges, and where it went out from. The rest comes off the
/// loan, and the screen says how much that is and what will still be owed
/// before anything is saved.
///
/// The instalment and the interest are filled in when the loan's terms say
/// what they are, the interest at the loan's rate for the days since it was
/// last paid. Both are suggestions: the bank's slip is the truth, and the
/// shopkeeper types over them. Once the interest has been typed, changing
/// the date no longer changes it.
class RepayLoanScreen extends ConsumerStatefulWidget {
  const RepayLoanScreen({required this.loan, super.key});

  final LoanView loan;

  @override
  ConsumerState<RepayLoanScreen> createState() => _RepayLoanScreenState();
}

class _RepayLoanScreenState extends ConsumerState<RepayLoanScreen> {
  final _paid = TextEditingController();
  final _interest = TextEditingController();
  final _charges = TextEditingController();
  final _note = TextEditingController();

  String? _from;
  BusinessDate? _date;
  bool _interestTyped = false;
  bool _paidTyped = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_suggest(BusinessDate.now(ref.read(appServicesProvider).clock)));
  }

  @override
  void dispose() {
    _paid.dispose();
    _interest.dispose();
    _charges.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Fills in what the loan's terms suggest for a payment on [on], leaving
  /// alone whatever the shopkeeper has typed.
  Future<void> _suggest(BusinessDate on) async {
    final ({Money paid, Money interest}) suggested;
    try {
      suggested = await ref
          .read(appServicesProvider)
          .loans
          .suggestRepayment(widget.loan.id, on);
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (!_interestTyped) {
        _interest.text = suggested.interest.isZero
            ? ''
            : _plain(suggested.interest);
      }
      if (!_paidTyped && suggested.paid.isPositive) {
        _paid.text = _plain(suggested.paid);
      }
    });
  }

  /// `7643.84`: what a numeric field takes, with no grouping.
  static String _plain(Money m) =>
      '${m.inPaisa ~/ 100}.${(m.inPaisa % 100).toString().padLeft(2, '0')}';

  Future<void> _save(String? from, BusinessDate date) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final paid = typedMoney(_paid.text);
    final interest = typedMoney(_interest.text);
    final charges = typedMoney(_charges.text);
    if (paid == null || interest == null || charges == null || from == null) {
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
      final no = await ref
          .read(appServicesProvider)
          .loans
          .repay(
            RepaymentDraft(
              loanId: widget.loan.id,
              paid: paid,
              interest: interest,
              charges: charges,
              fromPaymentAccountId: from,
              paidOn: date,
              note: _note.text,
            ),
          );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.loanRepaid(no))));
      navigator.pop();
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
    final (_, from) = MoneyAccountChips.resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      _from,
    );
    final loan = widget.loan;
    final rate = loan.terms?.rateBp;
    final principal =
        (typedMoney(_paid.text) ?? Money.zero) -
        (typedMoney(_interest.text) ?? Money.zero) -
        (typedMoney(_charges.text) ?? Money.zero);
    final after = loan.owed - principal;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.loanRepay)),
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
                  BlCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loan.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        BlAmountRow(
                          label: s.loanOwed,
                          labelStyle: TextStyle(
                            fontSize: 14,
                            color: t.inkMuted,
                          ),
                          child: BlMoney(loan.owed, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  LoanDateField(
                    date: date,
                    today: today,
                    onChanged: (d) {
                      setState(() => _date = d);
                      unawaited(_suggest(d));
                    },
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _paid,
                    label: s.loanPaid,
                    numeric: true,
                    onChanged: (_) => setState(() {
                      _paidTyped = true;
                      _failure = null;
                    }),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _interest,
                    label: s.loanInterest,
                    numeric: true,
                    onChanged: (_) => setState(() {
                      _interestTyped = true;
                      _failure = null;
                    }),
                  ),
                  if (rate != null && !_interestTyped) ...[
                    const SizedBox(height: BlTokens.space1),
                    Text(
                      s.loanInterestSuggested(formatBp(rate)),
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ],
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _charges,
                    label: s.loanCharges,
                    numeric: true,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlCard(
                    child: Column(
                      children: [
                        BlAmountRow(
                          label: s.loanPrincipalLine,
                          child: BlMoney(principal, size: 15),
                        ),
                        BlAmountRow(
                          label: s.loanAfterLine,
                          child: BlMoney(
                            after,
                            size: 15,
                            colour: after.isNegative ? t.danger : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  MoneyAccountChips(
                    label: s.loanFrom,
                    selectedId: from,
                    onSelected: (id) => setState(() => _from = id),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _note,
                    label: s.loanNotes,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                ],
              ),
            ),
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
                    label: s.loanRepaySave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_save(from, date)),
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
