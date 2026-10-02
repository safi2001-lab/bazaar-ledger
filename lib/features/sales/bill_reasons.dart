import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Why a bill was cancelled or put right, picked rather than typed (M36).
///
/// M31 gave a cancelled payment five reasons to pick from, on myBillBook's
/// model: a cancellation whose reason is one of a few words can be counted
/// and compared — how many bills were "rung twice" this month, and on whose
/// counter — where free text cannot, and FBR's rules for a POS-integrated
/// shop expect a cancelled invoice to carry a reason. A bill gets the same
/// treatment, with its own words: the reasons a BILL goes wrong are not a
/// payment's.
///
/// The rule is M31's, kept the same so the two sheets behave as one thing:
/// a reason is required — a preset picked, or words typed — "Other" takes
/// words, and the words typed after a preset are kept after it.
enum BillReason {
  // Why a bill is cancelled outright.
  orderCancelled,
  enteredTwice,
  wrongEntry,

  // Why a bill is put right and issued again.
  wrongItem,
  wrongQty,
  wrongPrice,
  wrongCustomer,

  other,
}

/// The presets a cancel offers.
const cancelReasons = [
  BillReason.orderCancelled,
  BillReason.enteredTwice,
  BillReason.wrongEntry,
  BillReason.other,
];

/// The presets "Ghalti theek karein" offers.
const correctReasons = [
  BillReason.wrongItem,
  BillReason.wrongQty,
  BillReason.wrongPrice,
  BillReason.wrongCustomer,
  BillReason.other,
];

String billReasonLabel(AppStrings s, BillReason reason) => switch (reason) {
  BillReason.orderCancelled => s.reasonOrderCancelled,
  // M31's own words, where the reason is the same one.
  BillReason.enteredTwice => s.reasonDuplicate,
  BillReason.wrongEntry => s.reasonWrongEntry,
  BillReason.wrongItem => s.reasonWrongItem,
  BillReason.wrongQty => s.reasonWrongQty,
  BillReason.wrongPrice => s.reasonWrongPrice,
  BillReason.wrongCustomer => s.reasonWrongCustomer,
  BillReason.other => s.reasonOther,
};

/// A reason being given: the preset picked, if any, and the words typed.
final class BillReasonController extends ChangeNotifier {
  BillReason? _picked;
  final detail = TextEditingController();

  BillReason? get picked => _picked;

  set picked(BillReason? value) {
    _picked = value;
    notifyListeners();
  }

  /// Whether the typed words are the whole reason: nothing picked, or Other.
  bool get wordsRequired => _picked == null || _picked == BillReason.other;

  /// The reason as the books keep it: the preset in words, then whatever
  /// was typed after it. Empty when nothing was picked or typed.
  String textIn(AppStrings s) {
    final typed = detail.text.trim();
    final picked = _picked;
    if (picked == null || picked == BillReason.other) return typed;
    final label = billReasonLabel(s, picked);
    return typed.isEmpty ? label : '$label: $typed';
  }

  @override
  void dispose() {
    detail.dispose();
    super.dispose();
  }
}

/// The preset chips and the words field under them.
class BillReasonPicker extends StatelessWidget {
  const BillReasonPicker({
    super.key,
    required this.reason,
    required this.presets,
    this.onChanged,
    this.autofocus = false,
  });

  final BillReasonController reason;
  final List<BillReason> presets;
  final VoidCallback? onChanged;
  final bool autofocus;

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
              for (final preset in presets)
                ChoiceChip(
                  selected: reason.picked == preset,
                  label: Text(billReasonLabel(s, preset)),
                  onSelected: (on) {
                    reason.picked = on ? preset : null;
                    onChanged?.call();
                  },
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: reason.detail,
            // The field is the reason itself until a preset is picked, and
            // is labelled so: "Wajah", as the sheet always asked.
            label: reason.wordsRequired ? s.voidReason : s.reasonDetail,
            autofocus: autofocus,
            onChanged: (_) => onChanged?.call(),
          ),
        ],
      ),
    );
  }
}
