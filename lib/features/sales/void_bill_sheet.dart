import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'bill_reasons.dart';

/// Cancelling a bill.
///
/// ## What a shopkeeper is actually agreeing to
///
/// Nothing is deleted. The bill keeps its number, its lines and its total, so
/// the paper the customer is holding still matches what the shop has; a
/// reversing entry is written against it and the stock comes back.
///
/// That is said on the sheet rather than left implied, because a shopkeeper
/// who believes a bill vanished will be surprised to find it in a report —
/// and being surprised by your own books is how you stop trusting them.
///
/// ## The reason is required
///
/// A void with no reason is a hole in the numbering nobody can account for
/// six months later, and it is the first thing an auditor asks about. The
/// domain refuses one; this asks for it in words first, so the refusal is
/// never what the shopkeeper meets.
///
/// Picked from presets since M36 — order cancelled, rung twice, a wrong
/// entry, or something else in words — as M31 did for payments, so a
/// month's cancellations can be counted by why. Typed words alone still do.
Future<bool> showVoidBillSheet(
  BuildContext context, {
  required String documentId,
  required String docNo,
}) async {
  final voided = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _VoidBillSheet(documentId: documentId, docNo: docNo),
  );
  return voided ?? false;
}

class _VoidBillSheet extends ConsumerStatefulWidget {
  const _VoidBillSheet({required this.documentId, required this.docNo});

  final String documentId;
  final String docNo;

  @override
  ConsumerState<_VoidBillSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_VoidBillSheet> {
  final _reason = BillReasonController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _void() async {
    if (_busy) return;
    final s = AppStrings.of(context);
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
    try {
      await services.voidDocument(
        services.actorNow(),
        documentId: widget.documentId,
        reason: why,
      );
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.voidDone(widget.docNo))));
      Navigator.of(context).pop(true);
    } on VoidRefused catch (refusal) {
      // Shown as words, not as an exception. A refusal naming the receipts
      // standing in the way is the whole point of the guard — dropping it
      // into a stack trace would waste it.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusal.reason;
      });
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
      // Scrolls: the reasons' chips and the keyboard together are taller
      // than a small phone at 200% text.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.voidTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              widget.docNo,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: t.inkFaint),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: Text(
                    s.voidExplain,
                    style: TextStyle(fontSize: 13, color: t.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space4),

            BillReasonPicker(
              reason: _reason,
              presets: cancelReasons,
              autofocus: true,
              onChanged: () => setState(() => _failure = null),
            ),

            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Container(
                padding: const EdgeInsets.all(BlTokens.space3),
                decoration: BoxDecoration(
                  color: t.dangerSurface,
                  borderRadius: BorderRadius.circular(BlTokens.radiusMd),
                ),
                child: Text(
                  _failure!,
                  style: TextStyle(fontSize: 13, color: t.danger),
                ),
              ),
            ],

            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.voidConfirm,
              icon: Icons.block,
              kind: BlButtonKind.danger,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_void()),
            ),
          ],
        ),
      ),
    );
  }
}
