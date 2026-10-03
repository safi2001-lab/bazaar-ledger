import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'control_providers.dart';

/// Credit control at the payment sheet (M68).
///
/// The sheet asks before it saves: which of the shop's rules this bill
/// would break -- the limit (or a temporary one), the count of open bills,
/// the age of the oldest, a bounced cheque still owed -- each said with its
/// figures, in the place the cashier is already looking. Not a dialog, as
/// M3's limit was not.
///
/// A rule set to warn is the cashier's call: "Phir bhi udhaar dein" and
/// Save. A rule set to block is the owner's: the button asks for their PIN
/// and a reason, beneath the screen, as the bill is written -- the sale
/// path judges it again inside the bill's own transaction and refuses it
/// without them, so a second till that changed the figures, or a screen
/// that forgot to ask, is held to the same rule. Cash is never refused.

/// What the shop's rules say about a bill for [partyId] leaving [owed] on
/// the khata, read now. Null, rather than a failure, when it cannot be
/// read: the sale path judges the bill again either way.
Future<CreditVerdict?> creditVerdictAtCounter(
  WidgetRef ref, {
  required String partyId,
  required Money owed,
  bool byCheque = false,
}) async {
  try {
    return await ref
        .read(appServicesProvider)
        .credit
        .atCounter(partyId: partyId, owed: owed, byCheque: byCheque);
  } on Object {
    return null;
  }
}

/// The rules [verdict] found, and the way past them.
class CreditRulesCard extends ConsumerStatefulWidget {
  const CreditRulesCard({
    super.key,
    required this.verdict,
    required this.partyId,
    required this.onGoOn,
  });

  final CreditVerdict verdict;
  final String partyId;

  /// The cashier goes on: past a warning, or to the owner past a block.
  final VoidCallback onGoOn;

  @override
  ConsumerState<CreditRulesCard> createState() => _CreditRulesCardState();
}

class _CreditRulesCardState extends ConsumerState<CreditRulesCard> {
  bool _busy = false;
  String? _failure;

  /// Zoho's "raise limit and save", for the owner: the limit taken to where
  /// this bill lands, for today only, and the bill saved.
  Future<void> _raise(Money to) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref
          .read(appServicesProvider)
          .credit
          .raiseForToday(widget.partyId, to);
      if (!mounted) return;
      ref.bumpRefresh();
      widget.onGoOn();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final verdict = widget.verdict;
    final blocks = verdict.blocks;
    final colour = blocks ? t.danger : t.warning;
    final onlyBounce = verdict.breaches.every(
      (b) => b.rule == CreditRule.bounce,
    );
    final limit = verdict.of(CreditRule.limit);
    // The owner may raise the limit when the limit is all that blocks.
    final mayRaise =
        blocks &&
        limit != null &&
        verdict.blocking.length == 1 &&
        verdict.blocking.single.rule == CreditRule.limit &&
        ref.watch(appServicesProvider).credit.mayChange;

    return Container(
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: blocks ? t.dangerSurface : t.warningSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocks) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, size: 18, color: colour),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: Text(
                    s.creditBlockedTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space2),
          ],
          for (final breach in verdict.breaches)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    breach.blocks
                        ? Icons.report_gmailerrorred_outlined
                        : Icons.warning_amber_outlined,
                    size: 18,
                    color: breach.blocks ? t.danger : t.warning,
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          creditRuleTitle(s, breach.rule),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: breach.blocks ? t.danger : t.warning,
                          ),
                        ),
                        Text(
                          creditBreachText(s, breach),
                          style: TextStyle(
                            fontSize: 13,
                            color: breach.blocks ? t.danger : t.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (blocks) ...[
            Text(
              s.creditBlockedHint,
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space2),
            if (mayRaise) ...[
              BlButton(
                label: s.creditRaiseToday,
                icon: Icons.trending_up,
                kind: BlButtonKind.secondary,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_raise(limit.after!)),
              ),
              const SizedBox(height: BlTokens.space2),
            ],
            BlButton(
              label: s.creditOwnerAllow,
              icon: Icons.lock_open_outlined,
              kind: BlButtonKind.secondary,
              onPressed: _busy ? null : widget.onGoOn,
            ),
          ] else
            BlButton(
              label: onlyBounce
                  ? s.tenderChequeBouncedAllow
                  : s.tenderOverLimitAllow,
              kind: BlButtonKind.secondary,
              onPressed: widget.onGoOn,
            ),
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
        ],
      ),
    );
  }
}
