import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/quick_party_sheet.dart' show refusalWords;
import 'entry_actions.dart';
import 'khata_providers.dart';

/// Writing a customer's udhaar off as a bad debt (M44).
///
/// The whole balance, or the bills the shopkeeper picks; and a reason,
/// which is not optional — "why did we give up on Aslam?" is the first
/// thing anybody asks of a write-off a year later. The money goes to the
/// Bad Debts expense, so the profit and loss shows it, and the khata shows
/// it as a line. Cancelled from that line like a receipt (M31), the udhaar
/// comes back exactly as it was.
Future<bool> showWriteOffSheet(
  BuildContext context, {
  required PartySummary party,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WriteOffSheet(party: party),
  );
  return done ?? false;
}

/// Why a balance is given up on, picked rather than typed so a year of
/// write-offs can be counted by cause.
enum WriteOffReason { movedAway, passedAway, refuses, closedDown, other }

String writeOffReasonLabel(AppStrings s, WriteOffReason reason) =>
    switch (reason) {
      WriteOffReason.movedAway => s.writeOffReasonMoved,
      WriteOffReason.passedAway => s.writeOffReasonDied,
      WriteOffReason.refuses => s.writeOffReasonRefused,
      WriteOffReason.closedDown => s.writeOffReasonClosed,
      WriteOffReason.other => s.reasonOther,
    };

class _WriteOffSheet extends ConsumerStatefulWidget {
  const _WriteOffSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_WriteOffSheet> createState() => _WriteOffSheetState();
}

class _WriteOffSheetState extends ConsumerState<_WriteOffSheet> {
  bool _whole = true;
  final _bills = <String>{};
  WriteOffReason? _reason;
  final _detail = TextEditingController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  String _why(AppStrings s) {
    final typed = _detail.text.trim();
    final picked = _reason;
    if (picked == null || picked == WriteOffReason.other) return typed;
    final label = writeOffReasonLabel(s, picked);
    return typed.isEmpty ? label : '$label: $typed';
  }

  Future<void> _save(List<OpenBill> open) async {
    // Before any await: two taps in one frame both reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    final why = _why(s);
    if (why.isEmpty) {
      setState(() => _failure = s.writeOffReasonRequired);
      return;
    }
    if (!_whole && _bills.isEmpty) {
      setState(() => _failure = s.writeOffPickBills);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final done = await services.udhaar.writeOff(
        widget.party.id,
        reason: why,
        documentIds: _whole ? null : _bills.toList(),
        amount: _whole
            ? widget.party.balance
            : Money.sum([
                for (final b in open)
                  if (_bills.contains(b.documentId)) b.outstanding,
              ]),
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.writeOffSaved(done.paymentNo, done.amount.amountOnly),
          ),
        ),
      );
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusalWords(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final open =
        ref.watch(openBillsProvider(widget.party.id)).valueOrNull ??
        const <OpenBill>[];

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
              s.writeOffTitle,
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
            const SizedBox(height: BlTokens.space3),
            EntryNote(s.writeOffExplain),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.writeOffWhole(widget.party.balance.amountOnly),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
            if (open.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space2),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(s.writeOffWholeShort)),
                  ButtonSegment(value: false, label: Text(s.writeOffBills)),
                ],
                selected: {_whole},
                onSelectionChanged: (v) => setState(() {
                  _whole = v.first;
                  _failure = null;
                }),
              ),
            ],
            if (!_whole)
              for (final bill in open)
                CheckboxListTile(
                  value: _bills.contains(bill.documentId),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (on) => setState(() {
                    on ?? false
                        ? _bills.add(bill.documentId)
                        : _bills.remove(bill.documentId);
                    _failure = null;
                  }),
                  title: Text('${bill.docNo} · ${bill.dateLocal}'),
                  secondary: BlMoney(bill.outstanding, size: 14),
                ),
            const SizedBox(height: BlTokens.space3),
            Text(
              s.writeOffWhy,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final reason in WriteOffReason.values)
                  ChoiceChip(
                    selected: _reason == reason,
                    label: Text(writeOffReasonLabel(s, reason)),
                    onSelected: (on) => setState(() {
                      _reason = on ? reason : null;
                      _failure = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _detail,
              label: _reason == null || _reason == WriteOffReason.other
                  ? s.writeOffReasonText
                  : s.reasonDetail,
              onChanged: (_) => setState(() => _failure = null),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              EntryProblem(_failure!),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.writeOffSave,
              icon: Icons.money_off_outlined,
              kind: BlButtonKind.danger,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save(open)),
            ),
          ],
        ),
      ),
    );
  }
}
