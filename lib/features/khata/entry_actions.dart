import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What every "open an entry and put it right" page shares (M31).
///
/// A payment, a charge, an expense and an opening balance are four different
/// pages, and they have to behave as one thing: the same question before a
/// cancellation, the same refusal shown the same way, the same rule about
/// who may do it. Kept here once so the four cannot drift apart.

/// Whether whoever is signed in may cancel or correct an entry.
///
/// Asked of the screen only to decide what to offer. The service refuses
/// anyway (`AppServices.corrections` requires the permission), because a
/// hidden button is one forgotten screen away from being pressed.
bool canCorrect(WidgetRef ref) =>
    ref.read(appServicesProvider).can(Permission.correctEntries);

/// The reasons a shopkeeper picks from, rather than types.
///
/// myBillBook's model, and the one a shop with staff needs: a cancellation
/// whose reason is one of five words can be counted and compared — how many
/// receipts were "entered twice" this month, and by whom — where free text
/// cannot. FBR's rules for a POS-integrated shop expect a cancelled entry to
/// carry a reason too. "Other" still takes words.
enum ReasonPreset { wrongEntry, duplicate, wrongAmount, dispute, other }

String reasonLabel(AppStrings s, ReasonPreset preset) => switch (preset) {
  ReasonPreset.wrongEntry => s.reasonWrongEntry,
  ReasonPreset.duplicate => s.reasonDuplicate,
  ReasonPreset.wrongAmount => s.reasonWrongAmount,
  ReasonPreset.dispute => s.reasonDispute,
  ReasonPreset.other => s.reasonOther,
};

/// A reason being given: the preset picked, if any, and the words typed.
final class ReasonController extends ChangeNotifier {
  ReasonPreset? _preset;
  final detail = TextEditingController();

  ReasonPreset? get preset => _preset;

  set preset(ReasonPreset? value) {
    _preset = value;
    notifyListeners();
  }

  /// Whether the typed words are the whole reason: nothing picked, or Other.
  bool get wordsRequired => _preset == null || _preset == ReasonPreset.other;

  /// The reason as the books keep it: the preset in words, then whatever was
  /// typed after it. Empty when nothing was picked or typed.
  String textIn(AppStrings s) {
    final typed = detail.text.trim();
    final picked = _preset;
    if (picked == null || picked == ReasonPreset.other) return typed;
    final label = reasonLabel(s, picked);
    return typed.isEmpty ? label : '$label: $typed';
  }

  @override
  void dispose() {
    detail.dispose();
    super.dispose();
  }
}

/// The preset chips and the words field under them.
///
/// [required] is a cancellation's: with nothing picked, the field is the
/// reason itself and is labelled so. An edit's is not required, and its
/// field says so.
class ReasonPicker extends StatelessWidget {
  const ReasonPicker({
    super.key,
    required this.reason,
    this.required = false,
    this.onChanged,
  });

  final ReasonController reason;
  final bool required;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return ListenableBuilder(
      listenable: reason,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.reasonPick, style: TextStyle(fontSize: 13, color: t.inkMuted)),
          const SizedBox(height: BlTokens.space2),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              for (final preset in ReasonPreset.values)
                ChoiceChip(
                  selected: reason.preset == preset,
                  label: Text(reasonLabel(s, preset)),
                  onSelected: (on) {
                    reason.preset = on ? preset : null;
                    onChanged?.call();
                  },
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: reason.detail,
            label: !required
                ? s.entryEditReason
                : reason.wordsRequired
                ? s.voidReason
                : s.reasonDetail,
            onChanged: (_) => onChanged?.call(),
          ),
        ],
      ),
    );
  }
}

/// The reason given for an edit, or the plain one when none was.
///
/// A cancellation must say why and asks for it. An edit already says what
/// changed — the old figure and the new are both kept — so the reason is
/// offered rather than demanded, and the books still never hold a blank one.
String editReason(AppStrings s, ReasonController reason) {
  final given = reason.textIn(s);
  return given.isEmpty ? s.entryEditReasonDefault : given;
}

/// The open bills as they will stand once [editing]'s money is taken back
/// off them: what it put on each added back, and a bill it cleared listed
/// again. The same list, in the same order, the corrected payment will be
/// allocated against.
List<OpenBill> reopenedFor(List<OpenBill> open, PaymentDetail? editing) {
  if (editing == null || editing.settled.isEmpty) return open;
  final back = {for (final b in editing.settled) b.documentId: b};
  final bills = [
    for (final bill in open)
      if (back[bill.documentId] case final settled?)
        OpenBill(
          documentId: bill.documentId,
          dateLocal: bill.dateLocal,
          sequence: bill.sequence,
          outstanding: bill.outstanding + settled.amount,
          docNo: bill.docNo,
          docType: bill.docType,
        )
      else
        bill,
    for (final settled in editing.settled)
      if (!open.any((b) => b.documentId == settled.documentId))
        OpenBill(
          documentId: settled.documentId,
          dateLocal: settled.dateLocal,
          sequence: settled.sequence,
          outstanding: settled.amount,
          docNo: settled.docNo,
          docType: settled.docType,
        ),
  ];
  // Oldest first, then by place in the series: the writer's own order.
  bills.sort((a, b) {
    final byDate = a.dateLocal.compareTo(b.dateLocal);
    if (byDate != 0) return byDate;
    final bySeq = a.sequence.compareTo(b.sequence);
    return bySeq != 0 ? bySeq : a.documentId.compareTo(b.documentId);
  });
  return bills;
}

/// How money moved, in the shopkeeper's words.
String modeLabel(AppStrings s, String mode) => switch (mode) {
  'cash' => s.tenderModeCash,
  'easypaisa' => s.tenderModeEasypaisa,
  'jazzcash' => s.tenderModeJazzCash,
  'bank_transfer' => s.tenderModeBank,
  'raast' => s.tenderModeRaast,
  'card' => s.tenderModeCard,
  'cheque' => s.tenderModeCheque,
  // A settlement discount or a write-off (M44): nothing came.
  'adjustment' => s.tenderModeAdjustment,
  _ => mode,
};

/// Asks why, then cancels with [cancel]. Returns whether it was cancelled.
///
/// Nothing is deleted, and the sheet says so before the shopkeeper agrees,
/// for the same reason the bill's own Cancel does: a shopkeeper who believes
/// an entry vanished is surprised to find it in a report, and being
/// surprised by your own books is how you stop trusting them.
Future<bool> showCancelEntrySheet(
  BuildContext context, {
  required String no,
  required Future<void> Function(AppServices services, String reason) cancel,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CancelEntrySheet(no: no, cancel: cancel),
  );
  return done ?? false;
}

class _CancelEntrySheet extends ConsumerStatefulWidget {
  const _CancelEntrySheet({required this.no, required this.cancel});

  final String no;
  final Future<void> Function(AppServices services, String reason) cancel;

  @override
  ConsumerState<_CancelEntrySheet> createState() => _CancelEntrySheetState();
}

class _CancelEntrySheetState extends ConsumerState<_CancelEntrySheet> {
  final _reason = ReasonController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    // First statement, before any await: two taps in one frame would
    // otherwise both reach the write.
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.cancel(services, why);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.voidDone(widget.no))));
      navigator.pop(true);
    } on Object catch (error) {
      // A refusal is words the shopkeeper can act on — which receipt is in
      // the way, that the cheque is at the bank — and is shown as such.
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.entryCancelTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(widget.no, style: TextStyle(fontSize: 14, color: t.inkMuted)),
            const SizedBox(height: BlTokens.space3),
            EntryNote(s.entryCancelExplain),
            const SizedBox(height: BlTokens.space4),
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
              label: s.voidConfirm,
              icon: Icons.block,
              kind: BlButtonKind.danger,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_cancel()),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet line of explanation, with an info mark.
class EntryNote extends StatelessWidget {
  const EntryNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: t.inkFaint),
        const SizedBox(width: BlTokens.space2),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: t.inkFaint)),
        ),
      ],
    );
  }
}

/// A refusal or a failure, in words, on a tinted panel.
class EntryProblem extends StatelessWidget {
  const EntryProblem(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Container(
      padding: const EdgeInsets.all(BlTokens.space3),
      decoration: BoxDecoration(
        color: t.dangerSurface,
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: t.danger)),
    );
  }
}

/// One labelled fact on an entry's page: "Date — 23-08-2026".
class EntryLine extends StatelessWidget {
  const EntryLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 14, color: t.ink)),
          ),
        ],
      ),
    );
  }
}
