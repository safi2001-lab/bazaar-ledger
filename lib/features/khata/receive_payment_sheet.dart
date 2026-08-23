import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'khata_providers.dart';

/// Taking money against a customer's khata.
///
/// ## The preview is the feature
///
/// A wholesale customer hands over Rs 50,000 against four open bills. Every
/// competing product in this market either nets it against one running
/// balance or makes the cashier tick boxes, and being unable to answer *which
/// bills did this settle* is the single most-complained-about gap in their
/// reviews. A shopkeeper who cannot answer it cannot argue with a customer
/// about it either.
///
/// So the sheet shows the answer before the money is taken, and it computes
/// it with `allocateFifo` — the same function the writer runs inside its own
/// transaction, over rows read with the same `WHERE` and the same `ORDER BY`.
/// A preview that could disagree with the write would be worse than none.
///
/// It can still differ in one way, and only one: a second till may settle a
/// bill between this being drawn and Save being tapped. The writer re-reads
/// inside the transaction, so the write is right and the preview was stale —
/// which is the correct direction for that error to run.
Future<bool> showReceivePaymentSheet(
  BuildContext context, {
  required PartySummary party,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReceivePaymentSheet(party: party),
  );
  return saved ?? false;
}

class _ReceivePaymentSheet extends ConsumerStatefulWidget {
  const _ReceivePaymentSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_ReceivePaymentSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_ReceivePaymentSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _chequeNo = TextEditingController();
  final _chequeBank = TextEditingController();

  String _mode = 'cash';
  String? _accountId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefilled with what they owe, because that is what a customer settling
    // up hands over. The cashier overtypes it when they do not.
    if (widget.party.balance.isPositive) {
      _amount.text = widget.party.balance.amountOnly.replaceAll(',', '');
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _chequeNo.dispose();
    _chequeBank.dispose();
    super.dispose();
  }

  Money get _entered {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return Money.zero;
    return Money.tryParse(raw) ?? Money.zero;
  }

  Future<void> _save(List<OpenBill> bills, String? accountId) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!_entered.isPositive) {
      setState(() => _error = s.wasooliAmountRequired);
      return;
    }
    if (_mode == 'cheque' && _chequeNo.text.trim().isEmpty) {
      setState(() => _error = s.wasooliChequeNoRequired);
      return;
    }
    if (accountId == null) {
      setState(() => _error = s.tenderNoAccount);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final receipt = await services.recordReceipt(
        services.actorNow(),
        ReceiptDraft(
          partyId: widget.party.id,
          amount: _entered,
          mode: _mode,
          paymentAccountId: accountId,
          reference: _reference.text.trim().isEmpty
              ? null
              : _reference.text.trim(),
          chequeNo: _mode == 'cheque' ? _chequeNo.text.trim() : null,
          chequeBank: _mode == 'cheque' && _chequeBank.text.trim().isNotEmpty
              ? _chequeBank.text.trim()
              : null,
        ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.wasooliSaved(receipt.amount.amountOnly))),
      );
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bills = ref.watch(openBillsProvider(widget.party.id));
    final accounts = ref.watch(paymentAccountsProvider);

    // Chosen when the accounts arrive rather than in initState, because they
    // are read asynchronously and a null here is a Save that fails at the
    // last step, after the customer has already handed the money over.
    //
    // Resolved for this build rather than stored, so `build` stays free of
    // side effects and a rebuild cannot fight a post-frame callback.
    final available = accounts.valueOrNull ?? const <PaymentAccountSummary>[];
    final resolvedAccountId =
        _accountId ??
        (available.isEmpty
            ? null
            : available
                  .firstWhere((a) => a.isDefault, orElse: () => available.first)
                  .id);

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        // The keyboard, not the gesture bar: a cashier types an amount here
        // with a customer waiting, and viewInsets is the quantity that moves.
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.wasooliTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              widget.party.name,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),

            BlField(
              controller: _amount,
              label: s.wasooliAmount,
              numeric: true,
              autofocus: true,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BlTokens.space3),

            _ModePicker(
              mode: _mode,
              onChanged: (mode) => setState(() {
                _mode = mode;
                _error = null;
              }),
            ),

            if (_mode == 'cheque') ...[
              const SizedBox(height: BlTokens.space3),
              BlField(controller: _chequeNo, label: s.wasooliChequeNo),
              const SizedBox(height: BlTokens.space2),
              BlField(controller: _chequeBank, label: s.wasooliChequeBank),
            ] else ...[
              const SizedBox(height: BlTokens.space3),
              BlField(controller: _reference, label: s.wasooliReference),
            ],

            const SizedBox(height: BlTokens.space4),
            bills.when(
              loading: () => const BlSkeletonList(rows: 2),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) => _Preview(amount: _entered, bills: rows),
            ),

            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],

            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.wasooliSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _save(bills.valueOrNull ?? const [], resolvedAccountId),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which bills this payment will clear.
class _Preview extends StatelessWidget {
  const _Preview({required this.amount, required this.bills});

  final Money amount;
  final List<OpenBill> bills;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    if (!amount.isPositive) return const SizedBox.shrink();
    if (bills.isEmpty) {
      return BlCard(
        child: Text(
          s.wasooliSettlesNone,
          style: TextStyle(fontSize: 14, color: t.inkMuted),
        ),
      );
    }

    // The same function the writer runs. Not a reimplementation of it.
    final allocation = allocateFifo(amount, bills);
    final outstanding = {for (final b in bills) b.documentId: b.outstanding};

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.wasooliSettles,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: BlTokens.space2),
          for (final applied in allocation.allocations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      applied.documentId,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: t.ink),
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  // Cleared or only reduced. A shopkeeper reading this out to
                  // a customer needs to know which, and "part paid" is the
                  // half of the answer that starts arguments.
                  BlChip(
                    applied.amount >= outstanding[applied.documentId]!
                        ? s.actionDone
                        : s.khataOpenBills,
                    tone: applied.amount >= outstanding[applied.documentId]!
                        ? BlChipTone.good
                        : BlChipTone.warn,
                  ),
                  const SizedBox(width: BlTokens.space2),
                  BlMoney(applied.amount, size: 14),
                ],
              ),
            ),
          if (allocation.unapplied.isPositive) ...[
            const Divider(height: BlTokens.space4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.wasooliOnAccount,
                    style: TextStyle(fontSize: 14, color: t.inkMuted),
                  ),
                ),
                BlMoney(allocation.unapplied, size: 14),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// How the money arrived. A label on a ledger row, never an integration.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  static const _modes = <(String, IconData)>[
    ('cash', Icons.payments_outlined),
    ('easypaisa', Icons.smartphone_outlined),
    ('jazzcash', Icons.smartphone_outlined),
    ('bank_transfer', Icons.account_balance_outlined),
    ('cheque', Icons.receipt_long_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        for (final (value, icon) in _modes)
          ChoiceChip(
            selected: mode == value,
            avatar: Icon(icon, size: 18),
            label: Text(_label(s, value)),
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }

  static String _label(AppStrings s, String mode) => switch (mode) {
    'cash' => s.tenderModeCash,
    'easypaisa' => s.tenderModeEasypaisa,
    'jazzcash' => s.tenderModeJazzCash,
    'bank_transfer' => s.tenderModeBank,
    _ => s.tenderModeCheque,
  };
}
