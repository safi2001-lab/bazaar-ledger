import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Putting a charge on a customer's khata with no sale behind it: a debit
/// note.
///
/// The bank's fee on a bounced cheque, the transporter's fare for goods sent
/// to them. Owed like a bill and settled by the same receipts, and never in
/// the day's sales.
Future<bool> showChargeSheet(
  BuildContext context, {
  required PartySummary party,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ChargeSheet(party: party),
  );
  return saved ?? false;
}

class _ChargeSheet extends ConsumerStatefulWidget {
  const _ChargeSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends ConsumerState<_ChargeSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _error = s.chargeNeedsAmount);
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _error = s.chargeNeedsNote);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final services = ref.read(appServicesProvider);
      await services.chargeParty(
        services.actorNow(),
        DebitNoteDraft(
          partyId: widget.party.id,
          partyName: widget.party.name,
          amount: amount,
          note: _note.text,
        ),
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.chargeSaved(amount.amountOnly))),
      );
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is DebitNoteRefused ? error.reason : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

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
              s.chargeTitle,
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
              label: s.chargeAmount,
              numeric: true,
              autofocus: true,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _note,
              label: s.chargeNote,
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.chargeSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
