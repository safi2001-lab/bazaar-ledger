import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pharmacy/batch_hold_sheet.dart';

typedef _Where = ({
  Map<String, Qty> places,
  List<String> known,
  List<LotOnHand> lots,
});

final _whereProvider = FutureProvider.autoDispose.family<_Where, String>((
  ref,
  itemId,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) {
    return (
      places: <String, Qty>{},
      known: const <String>[],
      lots: const <LotOnHand>[],
    );
  }
  return (
    places: await services.queries.stockByLocation(firm.id, itemId),
    known: await services.queries.stockLocations(firm.id),
    lots: await services.queries.lotsOnHand(firm.id, itemId: itemId),
  );
});

/// Where an item is: how much on the shop floor and in each godown, which
/// batches or serial numbers are on hand with their expiry, and a way to
/// move goods from one place to another.
class StockPlacesScreen extends ConsumerStatefulWidget {
  const StockPlacesScreen({required this.item, super.key});

  final ItemSummary item;

  @override
  ConsumerState<StockPlacesScreen> createState() => _StockPlacesScreenState();
}

class _StockPlacesScreenState extends ConsumerState<StockPlacesScreen> {
  final _qty = TextEditingController();
  final _to = TextEditingController(text: 'GODOWN');
  String _from = 'MAIN';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _move() async {
    final qty = Qty.tryParse(_qty.text);
    if (qty == null || _busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      await services.catalogue.transferStock(
        services.actorNow(),
        StockTransferDraft(
          itemId: widget.item.id,
          qty: qty,
          from: _from,
          to: _to.text.trim().toUpperCase(),
        ),
      );
      _qty.clear();
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.placesMoved)));
      if (mounted) setState(() => _busy = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is StockRefused ? error.reason : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final item = widget.item;
    final where = ref.watch(_whereProvider(item.id));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(item.name)),
      body: SafeArea(
        child: where.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (w) => ListView(
            padding: const EdgeInsets.all(BlTokens.space4),
            children: [
              BlSectionHeader(s.placesTitle),
              const SizedBox(height: BlTokens.space2),
              for (final MapEntry(key: place, value: qty) in w.places.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space1),
                  child: BlCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            place == 'MAIN' ? s.placesMain : place,
                            style: TextStyle(fontSize: 15, color: t.ink),
                          ),
                        ),
                        Text(
                          '${qty.display} ${item.unitCode}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (w.lots.isNotEmpty) ...[
                const SizedBox(height: BlTokens.space4),
                BlSectionHeader(
                  item.tracksSerial ? s.placesSerials : s.placesBatches,
                ),
                const SizedBox(height: BlTokens.space2),
                for (final lot in w.lots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space1),
                    child: BlCard(
                      // M49: a batch is put on hold, or let go, from here.
                      onTap:
                          item.tracksBatch &&
                              ref
                                  .read(appServicesProvider)
                                  .pharmacy
                                  .canMoveBatches
                          ? () => showBatchHoldSheet(
                              context,
                              lotId: lot.lotId,
                              lotNo: lot.lotNo,
                              itemName: item.name,
                              holdReason: lot.holdReason,
                            )
                          : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lot.lotNo,
                                  style: TextStyle(fontSize: 15, color: t.ink),
                                ),
                                if (lot.holdReason case final reason?)
                                  Text(
                                    s.pharmacyHeld(reason),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: t.danger,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (lot.expiry case final expiry?)
                            BlChip(
                              expiry.value,
                              tone:
                                  expiry.value.compareTo(
                                        BusinessDate.now(
                                          ref.read(appServicesProvider).clock,
                                        ).value,
                                      ) <
                                      0
                                  ? BlChipTone.bad
                                  : BlChipTone.neutral,
                            ),
                          const SizedBox(width: BlTokens.space2),
                          Text(
                            lot.qty.display,
                            style: TextStyle(fontSize: 15, color: t.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: BlTokens.space4),
              BlSectionHeader(s.placesMove),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                children: [
                  for (final place in w.known)
                    ChoiceChip(
                      selected: place == _from,
                      label: Text(place == 'MAIN' ? s.placesMain : place),
                      onSelected: (_) => setState(() => _from = place),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  Expanded(
                    child: BlField(
                      controller: _qty,
                      label: '${s.posQty} (${item.unitCode})',
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: BlField(controller: _to, label: s.placesTo),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: BlTokens.space2),
                Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
              ],
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.placesMoveButton,
                icon: Icons.swap_horiz,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_move()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
