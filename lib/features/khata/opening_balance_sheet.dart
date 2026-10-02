import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'entry_actions.dart';

/// Correcting what a party owed on the day their khata started (M31).
///
/// The figure was typed once, from the old register, and until M31 could
/// never be changed: the editor dropped the field the moment the party was
/// saved. A Rs 45,000 typed as Rs 4,500 then stayed wrong for ever.
///
/// It is corrected the append-only way, like everything else: the opening
/// entry is reversed and the right one posted, and the sheet says so before
/// the shopkeeper agrees. A reason is required — a starting balance that
/// changes with no explanation is exactly the restated khata the old rule
/// was afraid of.
Future<bool> showOpeningBalanceSheet(
  BuildContext context, {
  required String partyId,
  required String partyName,
  required Money current,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _OpeningBalanceSheet(
      partyId: partyId,
      partyName: partyName,
      current: current,
    ),
  );
  return saved ?? false;
}

class _OpeningBalanceSheet extends ConsumerStatefulWidget {
  const _OpeningBalanceSheet({
    required this.partyId,
    required this.partyName,
    required this.current,
  });

  final String partyId;
  final String partyName;
  final Money current;

  @override
  ConsumerState<_OpeningBalanceSheet> createState() =>
      _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends ConsumerState<_OpeningBalanceSheet> {
  final _amount = TextEditingController();
  final _reason = ReasonController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final raw = _amount.text.trim().replaceAll(',', '');
    final amount = raw.isEmpty ? null : Money.tryParse(raw);
    if (amount == null || amount.isNegative) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    final why = _reason.textIn(s);
    if (why.isEmpty) {
      setState(() => _failure = s.voidReasonRequired);
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
      await services.corrections.correctOpening(
        services.actorNow(),
        partyId: widget.partyId,
        opening: amount,
        reason: why,
      );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.openingSaved)));
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayCorrect = canCorrect(ref);

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
              s.openingTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              widget.partyName,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.openingNow,
                    style: TextStyle(fontSize: 14, color: t.inkMuted),
                  ),
                ),
                BlMoney(widget.current, size: 18, withSymbol: true),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            if (!mayCorrect)
              EntryNote(s.entryNotAllowed)
            else ...[
              EntryNote(s.openingExplain),
              const SizedBox(height: BlTokens.space4),
              BlField(
                controller: _amount,
                label: s.openingNew,
                numeric: true,
                autofocus: true,
                onChanged: (_) => setState(() => _failure = null),
              ),
              const SizedBox(height: BlTokens.space3),
              ReasonPicker(
                reason: _reason,
                required: true,
                onChanged: () => setState(() => _failure = null),
              ),
              if (_failure != null) ...[
                const SizedBox(height: BlTokens.space3),
                EntryProblem(_failure!),
              ],
              const SizedBox(height: BlTokens.space4),
              BlButton(
                label: s.openingCorrect,
                icon: Icons.check,
                big: true,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_save()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
