import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/shelf_guard.dart';

/// Goods handed over from the khata with the rate to be agreed (M55).
///
/// The household that settles on salary day sends the boy for ten kilos of
/// ghee and a bori of atta, and nobody names a price: the price is whatever
/// it is on the day they settle. The shopkeeper opens the customer's khata,
/// picks the goods and the quantities, and the goods are written down — a
/// challan with no rate, off the shelf at what they cost, owing nothing yet.
///
/// The counter can do the same from a bill already rung ("Rate baad mein"
/// beside "Challan banayein"); this is for the shopkeeper standing at the
/// khata, who has a name and a list and no bill to ring.
Future<void> showGiveGoodsSheet(
  BuildContext context, {
  required PartySummary party,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _GiveGoodsSheet(party: party),
);

/// One item picked, and how much of it.
final class _Picked {
  _Picked(this.item);

  final ItemSummary item;
  final qty = TextEditingController();
}

class _GiveGoodsSheet extends ConsumerStatefulWidget {
  const _GiveGoodsSheet({required this.party});

  final PartySummary party;

  @override
  ConsumerState<_GiveGoodsSheet> createState() => _GiveGoodsSheetState();
}

class _GiveGoodsSheetState extends ConsumerState<_GiveGoodsSheet> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _picked = <_Picked>[];
  List<ItemSummary> _found = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    for (final p in _picked) {
      p.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _find(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      setState(() => _found = const []);
      return;
    }
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return;
    final found = await services.queries.searchItems(
      firm.id,
      query: query,
      limit: 8,
    );
    // Only the answer to what is in the box now: a slow answer to an
    // earlier letter must not replace a quick one to the latest.
    if (!mounted || _search.text.trim() != query) return;
    setState(() => _found = found);
  }

  void _pick(ItemSummary item) {
    final s = AppStrings.of(context);
    // A piece sold by its serial number leaves as that piece, which is
    // picked at the counter by scanning it.
    if (item.tracksSerial) {
      setState(() => _error = s.giveGoodsSerial);
      return;
    }
    setState(() {
      _error = null;
      if (!_picked.any((p) => p.item.id == item.id)) _picked.add(_Picked(item));
      _found = const [];
      _search.clear();
    });
  }

  void _drop(_Picked p) => setState(() {
    _picked.remove(p);
    p.qty.dispose();
  });

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (_picked.isEmpty) {
      setState(() => _error = s.giveGoodsNothing);
      return;
    }
    final lines = <SaleLineDraft>[];
    for (final p in _picked) {
      final qty = Qty.tryParse(p.qty.text.trim());
      if (qty == null || !qty.isPositive) {
        setState(() => _error = s.giveGoodsQtyMissing);
        return;
      }
      lines.add(
        SaleLineDraft(
          itemId: p.item.id,
          itemName: p.item.name,
          itemCode: p.item.code,
          hsCode: p.item.hsCode,
          qty: qty,
          baseQty: qty,
          unitId: p.item.unitId,
          unitCode: p.item.unitCode,
          rate: Rate.zero,
          tracksStock: p.item.tracksStock,
        ),
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = ref.read(appServicesProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);

    // Never into thin air (M53): asked here in the item's own words, as the
    // counter asks; the challan path refuses a blocked item beneath this.
    if (!await _shelfAllows(lines)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final firm = await ref.read(firmProvider.future);
      final note = _note.text.trim();
      final given = await services.collections.giveRateLater(
        SaleDraft(
          lines: lines,
          partyId: widget.party.id,
          partyName: widget.party.name,
          roundToRupee: firm?.roundInvoiceToRupee ?? true,
          notes: note.isEmpty ? null : note,
        ),
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.giveGoodsSaved(given.docNo))),
      );
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<bool> _shelfAllows(List<SaleLineDraft> lines) async {
    final wanted = shelfWanted(lines);
    if (wanted.isEmpty) return true;
    final shelf = await ref
        .read(appServicesProvider)
        .shelf
        .atCounter(wanted.keys, locationCode: 'MAIN');
    if (!mounted) return false;
    final short = shelfShortfalls(wanted, shelf);
    final blocked = [
      for (final s in short)
        if (s.rule == NegativeStock.block) s,
    ];
    if (blocked.isNotEmpty) {
      await showShelfRefusal(context, blocked);
      return false;
    }
    if (short.isEmpty) return true;
    return askToSellShort(context, short);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(BlTokens.space4),
        children: [
          Text(
            s.goodsGivenRateLater,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            widget.party.name,
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          Text(
            s.giveGoodsHint,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          for (final p in _picked)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: t.ink),
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  SizedBox(
                    width: 140,
                    child: BlField(
                      controller: p.qty,
                      label: s.giveGoodsQty,
                      numeric: true,
                      decimals: p.item.unitDecimals,
                      suffix: Padding(
                        padding: const EdgeInsets.all(BlTokens.space3),
                        child: Text(p.item.unitCode),
                      ),
                    ),
                  ),
                  BlIconButton(
                    icon: Icons.close,
                    label: s.giveGoodsRemove,
                    onPressed: _busy ? null : () => _drop(p),
                  ),
                ],
              ),
            ),
          BlField(
            controller: _search,
            label: s.giveGoodsSearch,
            prefix: const Icon(Icons.search, size: 20),
            onChanged: (text) => unawaited(_find(text)),
          ),
          for (final item in _found)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space2),
              child: BlCard(
                onTap: () => _pick(item),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(fontSize: 15, color: t.ink),
                      ),
                    ),
                    if (item.tracksStock)
                      Text(
                        '${item.stockOnHand.display} ${item.unitCode}',
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                  ],
                ),
              ),
            ),
          if (_search.text.trim().isNotEmpty && _found.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space2),
              child: Text(
                s.emptyNoResults,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
          const SizedBox(height: BlTokens.space3),
          BlField(controller: _note, label: s.giveGoodsNote),
          if (_error != null) ...[
            const SizedBox(height: BlTokens.space3),
            Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.giveGoodsSave,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
