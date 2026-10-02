import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'entry_actions.dart';

/// Putting a charge on a customer's khata with no sale behind it: a debit
/// note.
///
/// The bank's fee on a bounced cheque, the transporter's fare for goods sent
/// to them. Owed like a bill and settled by the same receipts, and never in
/// the day's sales.
///
/// Handed [editing] (M31), it corrects a charge already put on: filled in
/// with it, and saved as one act that takes it back and puts the corrected
/// one on.
Future<bool> showChargeSheet(
  BuildContext context, {
  required PartySummary party,
  EntryDocument? editing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ChargeSheet(party: party, editing: editing),
  );
  return saved ?? false;
}

class _ChargeSheet extends ConsumerStatefulWidget {
  const _ChargeSheet({required this.party, this.editing});

  final PartySummary party;
  final EntryDocument? editing;

  @override
  ConsumerState<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends ConsumerState<_ChargeSheet> {
  late final _amount = TextEditingController(
    text: widget.editing?.total.amountOnly.replaceAll(',', ''),
  );
  late final _note = TextEditingController(text: widget.editing?.note);
  final _reason = ReasonController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reason.dispose();
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
      final draft = DebitNoteDraft(
        partyId: widget.party.id,
        partyName: widget.party.name,
        amount: amount,
        note: _note.text,
      );
      final editing = widget.editing;
      final String said;
      if (editing == null) {
        await services.chargeParty(services.actorNow(), draft);
        said = s.chargeSaved(amount.amountOnly);
      } else {
        final corrected = await services.corrections.editCharge(
          services.actorNow(),
          documentId: editing.id,
          draft: draft,
          reason: editReason(s, _reason),
        );
        said = s.entryEditSaved(corrected.cancelledNo, corrected.no);
      }
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(said)));
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          DebitNoteRefused(:final reason) => reason,
          VoidRefused(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final editing = widget.editing;

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
              editing == null ? s.chargeTitle : s.entryEditTitle(editing.docNo),
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
            if (editing != null) ...[
              const SizedBox(height: BlTokens.space2),
              EntryNote(s.entryEditExplain),
            ],
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
            if (editing != null) ...[
              const SizedBox(height: BlTokens.space3),
              ReasonPicker(reason: _reason),
            ],
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: editing == null ? s.chargeSave : s.entryEditSave,
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
