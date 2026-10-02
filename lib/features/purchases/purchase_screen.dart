import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_picker.dart';
import 'purchase_item_picker.dart';

/// Entering a delivery.
///
/// The screen that makes every margin figure in this app true. Until this
/// existed, `items.avg_cost_milli_paisa` was written once when an item was
/// created and never moved: a shop that opened rice at Rs 90 and had been
/// buying at Rs 120 for six months still read a Rs 30 profit on every sale.
///
/// ## Cost, not price
///
/// Every field here is what the shop PAID. The sale rate is not asked for and
/// not touched — a delivery arriving is not an instruction to reprice the
/// shelf, and a screen that changed both at once would make it impossible to
/// tell which decision a shopkeeper had actually made.
///
/// ## The new average is shown per line
///
/// So the shopkeeper watches the cost move as they type rather than finding
/// out in a report a month later. It is also the fastest way to catch a
/// mistyped quantity: two hundred sacks at Rs 120 makes the average look
/// wrong immediately.
/// What the shelf holds of these items, keyed by their ids joined in order.
///
/// A string key rather than a list, because a family keyed on a fresh list
/// is a new provider on every rebuild.
final _costPositionsProvider = FutureProvider.autoDispose
    .family<Map<String, CostPosition>, String>((ref, key) async {
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null || key.isEmpty) return const {};
      return services.queries.costPositions(firm.id, key.split(','));
    });

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final _freight = TextEditingController();
  final _paid = TextEditingController();
  final _billNo = TextEditingController();

  final _lines = <PurchaseLineDraft>[];
  PartySummary? _supplier;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _freight.dispose();
    _paid.dispose();
    _billNo.dispose();
    super.dispose();
  }

  Money get _freightAmount => Money.tryParse(_freight.text) ?? Money.zero;
  Money get _paidAmount => Money.tryParse(_paid.text) ?? Money.zero;
  Money get _goods => Money.sum([for (final l in _lines) l.lineTotal]);
  Money get _total => _goods + _freightAmount;

  Future<void> _pickSupplier() async {
    // A mill nobody has entered yet is offered as a new supplier, made and
    // chosen without leaving the delivery (M32).
    final party = await showModalBottomSheet<PartySummary?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PartyPicker(newPartyType: 'supplier'),
    );
    if (party != null && mounted) {
      setState(() {
        _supplier = party;
        _failure = null;
      });
    }
  }

  Future<void> _addLine() async {
    final line = await showPurchaseItemPicker(context);
    if (line != null && mounted) {
      setState(() {
        _lines.add(line);
        _failure = null;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);

    if (_supplier == null) {
      setState(() => _failure = s.purchaseSupplierRequired);
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _failure = s.purchaseNoLines);
      return;
    }
    if (_paidAmount > _total) {
      // Money handed over beyond a bill is an advance to the supplier, not
      // part of what this delivery cost. Caught here so the shopkeeper is
      // told which field is wrong rather than shown an exception.
      setState(() => _failure = s.purchasePaidTooMuch);
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final accounts = await services.queries.paymentAccounts(
      services.identity!.firmId,
    );

    try {
      final posted = await services.recordPurchase(
        services.actorNow(),
        PurchaseDraft(
          partyId: _supplier!.id,
          lines: _lines,
          freight: _freightAmount,
          paid: _paidAmount,
          supplierBillNo: _billNo.text.trim().isEmpty
              ? null
              : _billNo.text.trim(),
          paymentAccountId: _paidAmount.isPositive
              ? accounts.firstWhere((a) => a.isDefault).id
              : null,
        ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.purchaseSaved(posted.docNo))));
      Navigator.of(context).pop();
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

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.purchaseTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _form(context, s, t)),
            // Pinned, not the last thing in the scroll. Whatever else is
            // squeezed out by the keyboard or a long delivery, saving is
            // still reachable — the same rule the counter follows with its
            // Charge button, and the reason a shopkeeper never has to scroll
            // to finish.
            _SaveBar(
              busy: _busy,
              failure: _failure,
              onSave: () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }

  /// The new average each line leaves its item at, computed by `landLines`
  /// — the function the builder posts from — over the position the writer
  /// will read. Null until the positions arrive, or if the draft cannot be
  /// landed yet; a preview that throws must not take the form down with it.
  List<Rate>? _newAverages() {
    if (_lines.isEmpty) return null;
    final ids = ({for (final l in _lines) l.itemId}.toList()..sort()).join(',');
    final positions = ref.watch(_costPositionsProvider(ids)).valueOrNull;
    if (positions == null) return null;
    try {
      return [
        for (final landed in landLines(
          PurchaseDraft(partyId: '', lines: _lines, freight: _freightAmount),
          positions,
        ))
          landed.change.after.avg,
      ];
    } on Object {
      return null;
    }
  }

  Widget _form(BuildContext context, AppStrings s, BlTokens t) => ListView(
    padding: EdgeInsets.fromLTRB(
      BlTokens.space4,
      BlTokens.space3,
      BlTokens.space4,
      MediaQuery.viewInsetsOf(context).bottom + BlTokens.space10 * 2,
    ),
    children: [
      BlCard(
        onTap: () => unawaited(_pickSupplier()),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined, size: 20, color: t.inkMuted),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Text(
                _supplier?.name ?? s.purchaseSupplier,
                style: TextStyle(
                  fontSize: 15,
                  color: _supplier == null ? t.inkMuted : t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: t.inkFaint),
          ],
        ),
      ),
      const SizedBox(height: BlTokens.space3),
      BlField(controller: _billNo, label: s.purchaseBillNo),
      const SizedBox(height: BlTokens.space4),

      if (_lines.isEmpty)
        BlEmpty(
          icon: Icons.inventory_2_outlined,
          title: s.purchaseNoLines,
          message: s.purchaseNoLinesHint,
        )
      else
        for (var i = 0; i < _lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: BlTokens.space2),
            child: _LineTile(
              line: _lines[i],
              newAverage: _newAverages()?[i],
              onRemove: () => setState(() => _lines.removeAt(i)),
            ),
          ),

      const SizedBox(height: BlTokens.space2),
      BlButton(
        label: s.purchaseAddItem,
        icon: Icons.add,
        kind: BlButtonKind.secondary,
        onPressed: () => unawaited(_addLine()),
      ),

      const SizedBox(height: BlTokens.space4),
      BlField(
        controller: _freight,
        label: s.purchaseFreight,
        numeric: true,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: BlTokens.space2),
      BlField(
        controller: _paid,
        label: s.purchasePaid,
        numeric: true,
        onChanged: (_) => setState(() => _failure = null),
      ),

      const SizedBox(height: BlTokens.space4),
      BlCard(
        child: Column(
          children: [
            _Row(label: s.purchaseGoods, amount: _goods),
            if (_freightAmount.isPositive)
              _Row(label: s.purchaseFreight, amount: _freightAmount),
            const Divider(height: BlTokens.space4),
            _Row(label: s.purchaseTotal, amount: _total, strong: true),
            if (_paidAmount.isPositive)
              _Row(label: s.purchaseOwing, amount: _total - _paidAmount),
          ],
        ),
      ),
    ],
  );
}

/// The Save button, and whatever went wrong, pinned above the gesture bar.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.busy,
    required this.failure,
    required this.onSave,
  });

  final bool busy;
  final String? failure;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Container(
      width: double.infinity,
      color: t.surface,
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space3,
        // The keyboard and the gesture bar are different quantities and both
        // can be non-zero. Taking the larger of the two puts the button above
        // whichever is actually in the way.
        bottom:
            BlTokens.space3 +
            (MediaQuery.viewInsetsOf(context).bottom > 0
                ? 0
                : MediaQuery.viewPaddingOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            Text(failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            const SizedBox(height: BlTokens.space2),
          ],
          BlButton(
            label: s.purchaseSave,
            icon: Icons.check,
            big: true,
            busy: busy,
            onPressed: busy ? null : onSave,
          ),
        ],
      ),
    );
  }
}

/// One line, with what it does to the cost.
class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.newAverage,
    required this.onRemove,
  });

  final PurchaseLineDraft line;

  /// What this line leaves the item's cost at, freight included. The fastest
  /// way to catch a mistyped quantity: two hundred sacks at Rs 120 makes the
  /// average look wrong at once.
  final Rate? newAverage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return BlCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  '${line.qty.display} ${line.unitCode} '
                  'x ${line.rate.amountOnly}',
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
                if (newAverage != null)
                  Text(
                    AppStrings.of(
                      context,
                    ).purchaseNewAverage(newAverage!.amountOnly),
                    style: TextStyle(fontSize: 13, color: t.accent),
                  ),
              ],
            ),
          ),
          BlMoney(line.lineTotal, size: 15),
          const SizedBox(width: BlTokens.space2),
          BlIconButton(
            icon: Icons.close,
            label: AppStrings.of(context).actionDelete,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.amount, this.strong = false});

  final String label;
  final Money amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 15 : 14,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: strong ? t.ink : t.inkMuted,
              ),
            ),
          ),
          BlMoney(amount, size: strong ? 18 : 14, withSymbol: strong),
        ],
      ),
    );
  }
}
