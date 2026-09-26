import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'khata_providers.dart';

/// Paying a supplier against what the shop owes them.
///
/// The receipt sheet turned around, and the preview is the feature here for
/// the same reason: the mill's munshi says "you still owe on the June bill",
/// and the shopkeeper needs to see which deliveries a payment clears before
/// the money leaves the drawer. It is computed with `allocateFifo` over the
/// rows the writer will read, so it cannot disagree with the write.
Future<bool> showPaySupplierSheet(
  BuildContext context, {
  required PartySummary party,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PaySupplierSheet(party: party),
  );
  return saved ?? false;
}

class _PaySupplierSheet extends ConsumerStatefulWidget {
  const _PaySupplierSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_PaySupplierSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_PaySupplierSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();

  String? _accountId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefilled with everything owed, because clearing the account is the
    // commonest payment. The shopkeeper overtypes it when it is not.
    if (widget.party.payable.isPositive) {
      _amount.text = widget.party.payable.amountOnly.replaceAll(',', '');
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Money get _entered {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return Money.zero;
    return Money.tryParse(raw) ?? Money.zero;
  }

  Future<void> _save(
    List<OpenBill> bills,
    PaymentAccountSummary? account,
  ) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!_entered.isPositive) {
      setState(() => _error = s.wasooliAmountRequired);
      return;
    }
    final owed = Money.sum([for (final b in bills) b.outstanding]);
    if (_entered > owed) {
      // Money beyond the bills would be an advance the supplier owes back,
      // and there is no account to hold it in yet. Said here with the figure,
      // so the shopkeeper knows what to type instead.
      setState(() => _error = s.payTooMuch(owed.amountOnly));
      return;
    }
    if (account == null) {
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
      final paid = await services.paySupplier(
        services.actorNow(),
        SupplierPaymentDraft(
          partyId: widget.party.id,
          amount: _entered,
          mode: account.modeLabel,
          paymentAccountId: account.id,
          reference: _reference.text.trim().isEmpty
              ? null
              : _reference.text.trim(),
        ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.paySaved(paid.amount.amountOnly))),
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
    final bills = ref.watch(openPayablesProvider(widget.party.id));
    final accounts = ref.watch(paymentAccountsProvider);

    // Every account except the cheque one: a cheque the shop writes is a
    // post-dated liability, and paying from Cheques in Hand is endorsing a
    // customer's paper over. Both are the M6 lifecycle's to record.
    final available = [
      for (final a in accounts.valueOrNull ?? const <PaymentAccountSummary>[])
        if (a.modeLabel != 'cheque') a,
    ];
    final account = available.isEmpty
        ? null
        : available.firstWhere(
            (a) => a.id == _accountId,
            orElse: () => available.firstWhere(
              (a) => a.isDefault,
              orElse: () => available.first,
            ),
          );

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
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
              s.payTitle,
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
              label: s.payAmount,
              numeric: true,
              autofocus: true,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.expensePaidFrom,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final a in available)
                  ChoiceChip(
                    selected: a.id == account?.id,
                    label: Text(a.name),
                    onSelected: (_) => setState(() {
                      _accountId = a.id;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _reference, label: s.wasooliReference),
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
              label: s.paySave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _save(bills.valueOrNull ?? const [], account),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which deliveries this payment clears.
class _Preview extends StatelessWidget {
  const _Preview({required this.amount, required this.bills});

  final Money amount;
  final List<OpenBill> bills;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    if (!amount.isPositive || bills.isEmpty) return const SizedBox.shrink();

    // The same function the builder runs. Not a reimplementation of it.
    final allocation = allocateFifo(amount, bills);
    final outstanding = {for (final b in bills) b.documentId: b.outstanding};
    final dates = {for (final b in bills) b.documentId: b.dateLocal};

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.paySettles,
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
                      dates[applied.documentId]!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: t.ink),
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  BlChip(
                    applied.amount >= outstanding[applied.documentId]!
                        ? s.actionDone
                        : s.khataOpenPayables,
                    tone: applied.amount >= outstanding[applied.documentId]!
                        ? BlChipTone.good
                        : BlChipTone.warn,
                  ),
                  const SizedBox(width: BlTokens.space2),
                  BlMoney(applied.amount, size: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
