import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/entry_actions.dart' show EntryNote, EntryProblem, modeLabel;
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../pos/scheme_book.dart'; // M54
import 'bill_again.dart';
import 'bill_reasons.dart';

/// "Ghalti theek karein": a bill with a mistake on it, cancelled and issued
/// again without typing it twice (M36).
///
/// A posted bill is never edited. The customer is holding it, and a number
/// that changes underneath a piece of paper somebody holds is how a shop
/// stops being trusted (the owner's rule, and the schema's). Vyapar edits
/// bills in place; Tally and myBillBook cancel and issue again, and that is
/// what this is — but in one step, because the cancel was never the hard
/// part. Retyping thirty lines to fix one price was.
///
/// So: why (Wrong item, Wrong quantity, Wrong price, Wrong customer, or
/// words), then the bill is cancelled through the ordinary cancel — every
/// refusal it has stands, a bill with a receipt against it most of all —
/// and its exact copy, at the prices and discounts it was billed at, opens
/// on the counter to be put right and saved as a new bill. The new bill
/// says which it replaced and the old one which replaced it.
///
/// ## The money
///
/// Cancelling a bill takes its own tenders off the books with it — in the
/// books' eyes the cashier hands the money back (M5). The customer has not
/// actually been handed anything, so the corrected bill's payment sheet
/// starts with exactly what was taken, in the way it came: the money the
/// customer gave is the money that pays the corrected bill. Corrected down,
/// the sheet shows the change to give back; corrected up, what is still to
/// take. Never nothing (the customer would owe what they paid), never the
/// new total (money taken twice).
///
/// And the cancellation is not provisional. If the corrected bill is never
/// saved, the old one stays cancelled and its money stays handed back —
/// the sheet says so before the shopkeeper agrees, because a cancel that
/// quietly depends on a later screen is one nobody can reason about.
Future<bool> showCorrectBillSheet(
  BuildContext context, {
  required String documentId,
  required String docNo,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CorrectBillSheet(documentId: documentId, docNo: docNo),
  );
  return done ?? false;
}

class _CorrectBillSheet extends ConsumerStatefulWidget {
  const _CorrectBillSheet({required this.documentId, required this.docNo});

  final String documentId;
  final String docNo;

  @override
  ConsumerState<_CorrectBillSheet> createState() => _CorrectBillSheetState();
}

class _CorrectBillSheetState extends ConsumerState<_CorrectBillSheet> {
  final _reason = BillReasonController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _correct() async {
    // First statement, before any await: two taps in one frame would
    // otherwise both reach the cancel.
    if (_busy) return;
    final s = AppStrings.of(context);
    final why = _reason.textIn(s);
    if (why.isEmpty) {
      setState(() => _failure = s.voidReasonRequired);
      return;
    }
    // Before anything is written: a bill cancelled with nowhere to put its
    // copy is a correction half made.
    if (!ref.read(cartProvider).isEmpty) {
      setState(() => _failure = s.quotationCounterBusy);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final cart = ref.read(cartProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    // Asked for before the first await, while this sheet is certainly
    // still on screen to ask.
    final firmFuture = ref.read(firmProvider.future);
    // A counter that cannot convert units still rings what it can (a line
    // in another unit keeps the price it was billed at), so a failure here
    // is no answer rather than an error left unheard.
    final unitsFuture = ref
        .read(unitConverterProvider.future)
        .then<UnitConverter?>((u) => u, onError: (Object _) => null);
    // M54: the shop's schemes, asked for while this sheet is still here.
    final schemesRead = ref
        .read(schemeBookProvider.future)
        .then((b) => b, onError: (Object _) => SchemeBook.empty);
    try {
      final firm = await firmFuture;
      if (firm == null) throw StateError(s.commonNothingSaved);
      // Read fresh, and BEFORE the cancel: the lines as billed and the money
      // the bill's own tenders hold right now. After the cancel those
      // tenders are void and would read as nothing paid.
      final copy = await services.queries.billCopy(firm.id, widget.documentId);
      if (copy == null || copy.isVoid) throw StateError(s.commonNothingSaved);
      final units = await unitsFuture;
      final built = await counterCopyOf(
        services,
        firm.id,
        copy,
        // The bill as it was rung, discounts and all: the point is to fix
        // one thing and keep the rest.
        rates: CopyRates.asBilled,
        // The cancel puts the very pieces back on the shelf; the corrected
        // bill sells them again.
        piecesBack: true,
        units: units,
        // M54: a bonus the counter gives again is not named as left out.
        book: await schemesRead,
      );
      if (built.lines.isEmpty) {
        throw StateError(
          [s.copyNothing(widget.docNo), ?leftOutWords(s, built)].join('\n'),
        );
      }

      await services.voidDocument(
        services.actorNow(),
        documentId: widget.documentId,
        reason: why,
      );

      cart.loadCopy(
        built.lines,
        party: built.party,
        billDiscount: built.billDiscount,
        replacesId: copy.documentId,
        replacesNo: copy.docNo,
        paidBefore: copy.paidBefore,
        copiedFromNo: copy.docNo,
        copyNote: leftOutWords(s, built),
      );
      container.bumpRefresh();
      // Only this sheet. Had it been swiped away while the cancel was being
      // written, a pop would take the bill's own screen instead.
      if (mounted) navigator.pop(true);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const PosScreen()),
        ),
      );
    } on VoidRefused catch (refusal) {
      // The cancel's own refusal, in its own words — the receipt that is in
      // the way, the cheque at the bank. Nothing was cancelled and nothing
      // went onto the counter.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusal.reason;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.message;
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
    final paid = ref
        .watch(billCopyProvider(widget.documentId))
        .valueOrNull
        ?.paidBefore;

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
              s.correctTitle,
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
            EntryNote(s.correctExplain),
            if (paid != null) ...[
              const SizedBox(height: BlTokens.space2),
              EntryNote(
                paid.onUdhaar
                    ? s.correctUdhaar
                    : s.correctPaid(
                        paid.amount.amountOnly,
                        modeLabel(s, paid.mode ?? 'cash'),
                      ),
              ),
            ],
            const SizedBox(height: BlTokens.space2),
            // Said before the shopkeeper agrees: the cancel does not wait
            // for the new bill.
            Container(
              padding: const EdgeInsets.all(BlTokens.space3),
              decoration: BoxDecoration(
                color: t.warningSurface,
                borderRadius: BorderRadius.circular(BlTokens.radiusMd),
              ),
              child: Text(
                paid == null || paid.onUdhaar
                    ? s.correctAbandon
                    : s.correctAbandonPaid(paid.amount.amountOnly),
                style: TextStyle(fontSize: 13, color: t.warning),
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            BillReasonPicker(
              reason: _reason,
              presets: correctReasons,
              onChanged: () => setState(() => _failure = null),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              EntryProblem(_failure!),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.correctConfirm,
              icon: Icons.published_with_changes_outlined,
              kind: BlButtonKind.danger,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_correct()),
            ),
          ],
        ),
      ),
    );
  }
}
