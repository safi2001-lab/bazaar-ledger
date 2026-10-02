import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/entry_actions.dart';

/// "Ghar le gaye": goods off the shelf for the house (M47).
///
/// The owner picks the item and says how much; the shelf goes down and the
/// owner's share of the shop goes down by what the goods cost, and the
/// profit is left alone. The price is never asked: goods taken home leave
/// at what they cost, which the books already know, and a shopkeeper asked
/// for a price types the sale price and books a margin nobody made.
///
/// Only the owner and the accountant reach this, from the home's side of
/// the expense screen; the service refuses anyone else. It pops `true` when
/// something was saved.
class HomeGoodsScreen extends ConsumerStatefulWidget {
  const HomeGoodsScreen({super.key});

  @override
  ConsumerState<HomeGoodsScreen> createState() => _HomeGoodsScreenState();
}

class _HomeGoodsScreenState extends ConsumerState<HomeGoodsScreen> {
  final _search = TextEditingController();
  final _qty = TextEditingController();
  final _note = TextEditingController();
  Timer? _debounce;
  String _query = '';
  ItemSummary? _item;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final item = _item;
    if (item == null) {
      setState(() => _failure = s.homeGoodsPick);
      return;
    }
    final qty = Qty.tryParse(_qty.text.trim());
    if (qty == null || !qty.isPositive) {
      setState(() => _failure = s.homeGoodsQtyInvalid);
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
      final taken = await services.shopMoney.takeGoodsHome(
        GoodsTakenHomeDraft(itemId: item.id, qty: qty, note: _note.text),
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.homeGoodsSaved(taken.docNo, 'Rs ${taken.amount.amountOnly}'),
          ),
        ),
      );
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          ExpenseRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final item = _item;
    final found = _query.isEmpty || item != null
        ? const <ItemSummary>[]
        : [
            for (final i
                in ref.watch(itemSearchProvider(_query)).valueOrNull ??
                    const <ItemSummary>[])
              if (i.tracksStock) i,
          ];

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.homeGoodsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space5,
                ),
                children: [
                  EntryNote(s.homeGoodsExplain),
                  const SizedBox(height: BlTokens.space4),
                  if (item == null) ...[
                    BlField(
                      controller: _search,
                      label: s.homeGoodsSearch,
                      autofocus: true,
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: BlTokens.space2),
                    for (final i in found.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space1),
                        child: BlCard(
                          onTap: () => setState(() {
                            _item = i;
                            _failure = null;
                          }),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  i.name,
                                  style: TextStyle(fontSize: 15, color: t.ink),
                                ),
                              ),
                              Text(
                                s.homeGoodsOnHand(
                                  '${i.stockOnHand.display} ${i.unitCode}',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: t.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ] else ...[
                    BlCard(
                      onTap: () => setState(() {
                        _item = null;
                        _failure = null;
                      }),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: t.inkMuted,
                          ),
                          const SizedBox(width: BlTokens.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: t.ink,
                                  ),
                                ),
                                Text(
                                  s.homeGoodsOnHand(
                                    '${item.stockOnHand.display} '
                                    '${item.unitCode}',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: t.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.close, size: 18, color: t.inkFaint),
                        ],
                      ),
                    ),
                    const SizedBox(height: BlTokens.space3),
                    BlField(
                      controller: _qty,
                      label: s.homeGoodsQty,
                      numeric: true,
                      decimals: item.unitDecimals,
                      suffix: Text(item.unitCode),
                      onChanged: (_) => setState(() => _failure = null),
                    ),
                    const SizedBox(height: BlTokens.space3),
                    BlField(controller: _note, label: s.homeGoodsNote),
                  ],
                ],
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
                    (MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 0
                        : MediaQuery.viewPaddingOf(context).bottom),
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
                    label: s.homeGoodsSave,
                    icon: Icons.home_outlined,
                    big: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => unawaited(_save()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
