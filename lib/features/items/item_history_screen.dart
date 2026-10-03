import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/counting.dart';
import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Where one item's stock went.
///
/// The question a shopkeeper asks is never "what is the balance" — they can see
/// the shelf. It is "there should be forty and there are thirty-one, where did
/// nine go", and the only honest answer is the list of movements with the bill
/// or the reason beside each one.
///
/// `stock_ledger` is append-only and the write path refuses to rewrite or
/// tombstone a row in it, so this is a reading of history rather than a
/// reconstruction of one. That is the whole reason the answer can be trusted,
/// and it is why the screen shows movements rather than a computed balance.
class ItemHistoryScreen extends ConsumerStatefulWidget {
  const ItemHistoryScreen({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.unitCode,
  });

  final String itemId;
  final String itemName;
  final String unitCode;

  @override
  ConsumerState<ItemHistoryScreen> createState() => _ItemHistoryScreenState();
}

class _ItemHistoryScreenState extends ConsumerState<ItemHistoryScreen> {
  final _scroll = ScrollController();
  final _movements = <StockMovement>[];

  bool _loading = true;
  bool _exhausted = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_loading || _exhausted) return;
    if (!_scroll.hasClients) return;
    // At four fifths of the way down, so the next page is usually already
    // there by the time a thumb reaches the bottom.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      if (firm == null || !mounted) return;

      // Keyset, not offset. The cursor is the last row already shown, so page
      // fifty costs what page one costs — and in a stock history the
      // interesting rows are usually the old ones, which is exactly where an
      // OFFSET would have got slow.
      const pageSize = 50;
      final page = await services.queries.stockMovements(
        firm.id,
        widget.itemId,
        afterId: _movements.isEmpty ? null : _movements.last.id,
        limit: pageSize,
      );
      if (!mounted) return;
      setState(() {
        _movements.addAll(page);
        // A SHORT page is the end, not just an empty one. Waiting for an empty
        // page costs an extra round trip on every history a shopkeeper opens,
        // and — worse — leaves the trailing spinner on screen until it
        // arrives. An animation that never stops is also an animation
        // `pumpAndSettle` never settles, so the test for this screen hung
        // rather than failed.
        _exhausted = page.length < pageSize;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.historyTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(
              left: BlTokens.space4,
              right: BlTokens.space4,
              bottom: BlTokens.space2,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.itemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(child: _body(s, t)),
    );
  }

  Widget _body(AppStrings s, BlTokens t) {
    if (_failure != null && _movements.isEmpty) {
      return BlError(
        title: s.commonSomethingWentWrong,
        message: _failure!,
        onRetry: _loadMore,
      );
    }
    if (_loading && _movements.isEmpty) return const BlSkeletonList();
    if (_movements.isEmpty) {
      return BlEmpty(icon: Icons.history, title: s.historyNone);
    }

    // M45: watched here, in the build, and handed to every row.
    final counting = countingOfItem(ref, widget.itemId, widget.unitCode);
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      itemCount: _movements.length + (_exhausted ? 0 : 1),
      separatorBuilder: (_, _) => Divider(height: 1, color: t.line),
      itemBuilder: (context, i) {
        if (i >= _movements.length) {
          return const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        return _MovementRow(
          movement: _movements[i],
          unitCode: widget.unitCode,
          // M45: "-(2 ctn + 5 pcs)", in the item's own packs.
          counting: counting,
        );
      },
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.unitCode,
    required this.counting,
  });

  final StockMovement movement;
  final String unitCode;
  final CountingLadder counting;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final out = movement.isOut;

    // Colour AND a sign AND a word. Roughly two in five adults in rural
    // Pakistan cannot read fluently, and colour alone is unreadable to anyone
    // colour-blind — so the direction is carried three ways.
    final label = switch (movement.txnType) {
      'opening' => s.historyOpening,
      'sale' => s.historySale,
      'sale_return' => s.historySaleReturn,
      'purchase' => s.historyPurchase,
      'adjustment' => s.historyAdjustment,
      'wastage' => s.historyWastage,
      _ => s.historyOther,
    };

    // The bill if there is one, the reason if there is not. A correction has
    // no document to look up, which is exactly why a reason is mandatory.
    final detail = movement.docNo ?? movement.reason;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BlTokens.space4,
        vertical: BlTokens.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            out ? Icons.arrow_downward : Icons.arrow_upward,
            size: 18,
            color: out ? t.moneyOut : t.money,
          ),
          const SizedBox(width: BlTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  movement.occurredOnLocal,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlQty(
                movement.qtyDelta,
                unit: unitCode,
                colour: out ? t.moneyOut : t.money,
                counting: counting,
              ),
              if (movement.balanceAfter case final Qty balance) ...[
                const SizedBox(height: 2),
                Text(
                  s.historyBalance(counting.words(balance)),
                  style: TextStyle(fontSize: 11, color: t.inkMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
