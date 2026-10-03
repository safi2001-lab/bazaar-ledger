import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/counting.dart';
import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Correcting what the shelf says.
///
/// Deliberately built around counting rather than around arithmetic. A
/// shopkeeper standing at the shelf knows one number — how many are there —
/// and does not want to work out a difference in their head while holding a
/// torch. They type what they counted; the difference is worked out against
/// the ledger inside the transaction, so two counters counting at once cannot
/// both write the same correction from the same stale figure.
///
/// The other shape, a write-off, is the one where the shopkeeper knows the
/// movement rather than the total: three tins broke. Same arithmetic,
/// different fact, and the ledger records which it was.
class StockAdjustSheet extends ConsumerStatefulWidget {
  const StockAdjustSheet({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.onHand,
    required this.unitCode,
  });

  final String itemId;
  final String itemName;
  final Qty onHand;
  final String unitCode;

  @override
  ConsumerState<StockAdjustSheet> createState() => _StockAdjustSheetState();
}

class _StockAdjustSheetState extends ConsumerState<StockAdjustSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _counted = TextEditingController(
    text: widget.onHand.display,
  );
  final _reason = TextEditingController();

  /// True for a stock take, false for a write-off.
  bool _isCount = true;
  bool _busy = false;
  Object? _failure;

  /// What was counted, in the item's own unit (M45): "3 ctn 7" as the shelf
  /// is stacked, as readily as "79". A figure alone is in the item's own
  /// unit, which is what this box was always in.
  Qty? _read(String? typed) => ref
      .read(countingBookProvider)
      .entryLadder(itemId: widget.itemId, baseUnitCode: widget.unitCode)
      .read(typed ?? '')
      ?.qty;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // First statement, before the validate and before any await. A disabled
    // button only disables on the next build, so two taps in one frame both
    // reach here — and this writes a ledger row and a journal entry.
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final typed = _read(_counted.text);
    if (typed == null) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    // Held across the await: backing out mid-write disposes this state, and
    // reaching through `ref` afterwards throws where the catch would swallow
    // it, leaving the correction written and the screen never refreshed.
    final container = ProviderScope.containerOf(context, listen: false);
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = AppStrings.of(context);

    try {
      await services.catalogue.adjustStock(
        services.actorNow(),
        _isCount
            ? StockAdjustmentDraft.counted(
                itemId: widget.itemId,
                counted: typed,
                reason: _reason.text.trim(),
              )
            : StockAdjustmentDraft.byDelta(
                itemId: widget.itemId,
                // What was typed is how much LEFT the shelf, so it goes on
                // the ledger as a negative. Asking a shopkeeper to type a
                // minus sign for breakage would be asking them to get it
                // wrong.
                change: Qty.raw(-typed.inThousandths),
                reason: _reason.text.trim(),
              ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.stockAdjustDone)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlSectionHeader(widget.itemName),
            const SizedBox(height: BlTokens.space2),
            BlAmountRow(
              label: s.stockAdjustCurrent,
              labelStyle: TextStyle(fontSize: 14, color: t.inkMuted),
              child: BlQty(
                widget.onHand,
                unit: widget.unitCode,
                size: 20,
                // M45: "2 ctn + 5 pcs" on the shelf now.
                counting: countingOfItem(ref, widget.itemId, widget.unitCode),
              ),
            ),
            const SizedBox(height: BlTokens.space4),

            // Which of the two this is. A recount and a breakage are the same
            // arithmetic and different facts, and the ledger says which.
            Row(
              children: [
                Expanded(
                  child: BlButton(
                    label: s.stockAdjustRecount,
                    kind: _isCount
                        ? BlButtonKind.primary
                        : BlButtonKind.secondary,
                    onPressed: () => setState(() {
                      _isCount = true;
                      _counted.text = widget.onHand.display;
                    }),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: BlButton(
                    label: s.stockAdjustWriteOff,
                    kind: _isCount
                        ? BlButtonKind.secondary
                        : BlButtonKind.primary,
                    onPressed: () => setState(() {
                      _isCount = false;
                      _counted.text = '';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space4),

            BlField(
              controller: _counted,
              label: _isCount ? s.stockAdjustCounted : s.stockAdjustWriteOff,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              validator: (value) {
                final qty = _read(value);
                if (qty == null) return s.commonRequired;
                if (qty.isNegative) return s.commonRequired;
                if (!_isCount && qty.isZero) return s.commonRequired;
                return null;
              },
            ),
            const SizedBox(height: BlTokens.space3),

            BlField(
              controller: _reason,
              label: s.stockAdjustReason,
              hint: s.stockAdjustReasonHint,
              // Required, and the writer refuses a blank one too. A stock
              // figure that can be changed without saying why is a figure
              // nobody can defend to an auditor, to a supplier, or to whoever
              // was on the counter that afternoon.
              validator: (value) => (value ?? '').trim().isEmpty
                  ? s.stockAdjustNeedsReason
                  : null,
            ),

            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                '$_failure',
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ],

            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.stockAdjustSave,
              icon: Icons.fact_check_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
