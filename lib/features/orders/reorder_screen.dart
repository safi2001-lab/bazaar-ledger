import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_picker.dart';
import 'order_list_screen.dart';
import 'order_providers.dart';

/// "Order banayein" (M41): what to order now, by supplier, and one tap to
/// put each supplier's on a purchase order.
///
/// What the shelf needs is M34's reorder quantity off the Low Stock list,
/// less what is already on a purchase order still to arrive; what the
/// counter wrote on the shortage list is added. Each item sits under the
/// supplier it last came from, at what it last cost; the quantities are the
/// shopkeeper's to change, a line can be struck off, and an item nobody has
/// supplied yet waits for a supplier to be picked.
class ReorderScreen extends ConsumerStatefulWidget {
  const ReorderScreen({super.key});

  @override
  ConsumerState<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends ConsumerState<ReorderScreen> {
  /// The quantities as typed, by item id. Starts at the suggestion.
  final _qty = <String, TextEditingController>{};

  /// Lines struck off.
  final _dropped = <String>{};

  /// The supplier picked for items no supplier has sent yet.
  PartySummary? _forOrphans;

  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(ReorderLine l) => _qty.putIfAbsent(
    l.itemId,
    () => TextEditingController(text: l.qty.display),
  );

  /// [group] as the shopkeeper has it now: struck lines gone, quantities as
  /// typed, and the picked supplier on items that had none. Null when a
  /// quantity cannot be read.
  ({String supplierId, List<OrderLineDraft> lines})? _edited(ReorderGroup g) {
    final supplierId = g.supplierId ?? _forOrphans?.id;
    if (supplierId == null) return null;
    final lines = <OrderLineDraft>[];
    for (final l in g.lines) {
      if (_dropped.contains(l.itemId)) continue;
      final qty = Qty.tryParse(_controller(l).text.trim());
      if (qty == null || qty.isNegative) return null;
      if (qty.isZero) continue;
      lines.add(l.copyWith(qty: qty).toOrderLine());
    }
    return (supplierId: supplierId, lines: lines);
  }

  Future<void> _make(List<ReorderGroup> groups) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final drafts = <OrderDraft>[];
    for (final g in groups) {
      final edited = _edited(g);
      if (edited == null) {
        if (g.supplierId == null && _forOrphans == null) continue;
        setState(() => _failure = s.orderItemNeeds);
        return;
      }
      if (edited.lines.isEmpty) continue;
      drafts.add(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: edited.supplierId,
          lines: edited.lines,
        ),
      );
    }
    if (drafts.isEmpty) {
      setState(() => _failure = s.reorderNothingPicked);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final made = await ref.read(appServicesProvider).orders.placeAll(drafts);
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.reorderMade(made.length))),
      );
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const OrderListScreen(kind: OrderKind.purchase),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is OrderRefused ? error.reason : '$error';
        });
      }
    }
  }

  Future<void> _pickSupplier() async {
    final party = await showModalBottomSheet<PartySummary?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PartyPicker(newPartyType: 'supplier'),
    );
    if (party != null && mounted) setState(() => _forOrphans = party);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final groups = ref.watch(reorderProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.ordersReorder)),
      body: SafeArea(
        child: groups.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(reorderProvider),
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: Icons.check_circle_outline,
                    title: s.reorderEmpty,
                    message: s.reorderEmptyHint,
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          BlTokens.space4,
                          BlTokens.space3,
                          BlTokens.space4,
                          MediaQuery.viewInsetsOf(context).bottom +
                              BlTokens.space6,
                        ),
                        children: [for (final g in list) ..._group(s, t, g)],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: t.surface,
                      padding: EdgeInsets.only(
                        left: BlTokens.space4,
                        right: BlTokens.space4,
                        top: BlTokens.space3,
                        bottom:
                            BlTokens.space3 +
                            MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_failure != null) ...[
                            Text(
                              _failure!,
                              style: TextStyle(color: t.danger, fontSize: 14),
                            ),
                            const SizedBox(height: BlTokens.space2),
                          ],
                          BlButton(
                            label: s.reorderMakeAll(
                              list
                                  .where(
                                    (g) =>
                                        g.supplierId != null ||
                                        _forOrphans != null,
                                  )
                                  .length,
                            ),
                            icon: Icons.playlist_add_check,
                            big: true,
                            busy: _busy,
                            onPressed: _busy
                                ? null
                                : () => unawaited(_make(list)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _group(AppStrings s, BlTokens t, ReorderGroup g) => [
    Padding(
      padding: const EdgeInsets.only(
        top: BlTokens.space3,
        bottom: BlTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              g.supplierName ?? _forOrphans?.name ?? s.reorderNoSupplier,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
          ),
          if (g.supplierId == null)
            BlButton(
              label: s.purchaseSupplier,
              kind: BlButtonKind.ghost,
              onPressed: () => unawaited(_pickSupplier()),
            )
          else
            BlButton(
              label: s.reorderMakeOne,
              kind: BlButtonKind.ghost,
              onPressed: _busy ? null : () => unawaited(_make([g])),
            ),
        ],
      ),
    ),
    for (final l in g.lines)
      if (!_dropped.contains(l.itemId))
        Padding(
          padding: const EdgeInsets.only(bottom: BlTokens.space2),
          child: BlCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.itemName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        s.reorderFacts(
                          l.stock.display,
                          l.sold.display,
                          l.onOrder.display,
                        ),
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                      if (l.wasAsked)
                        Padding(
                          padding: const EdgeInsets.only(top: BlTokens.space1),
                          child: BlChip(
                            s.reorderAsked,
                            tone: BlChipTone.warn,
                            icon: Icons.star,
                          ),
                        ),
                      if (l.rate != null)
                        Text(
                          '@ ${l.rate!.amountOnly} / ${l.unitCode}',
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: BlField(
                    controller: _controller(l),
                    label: l.unitCode,
                    numeric: true,
                    decimals: 3,
                  ),
                ),
                BlIconButton(
                  icon: Icons.close,
                  label: s.actionDelete,
                  onPressed: () => setState(() => _dropped.add(l.itemId)),
                ),
              ],
            ),
          ),
        ),
  ];
}
