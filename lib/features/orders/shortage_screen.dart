import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'order_providers.dart';
import 'reorder_screen.dart';
import 'send_order.dart';

/// The shortage list (M41): the "*" a cashier writes when a customer asks
/// for something the shelf does not have.
///
/// In most bazaar shops this is the back page of the khata register, read
/// out to the order-booker on his day; Marg calls it the shortage book and
/// MediStock the daily wishlist. Here it is written from the counter or the
/// items list in two taps, sent on WhatsApp as a list, put on the next
/// purchase order by the reorder screen, and a line naming an item leaves
/// it by itself when a delivery of that item is entered.
class ShortageScreen extends ConsumerWidget {
  const ShortageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final list = ref.watch(shortageProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.ordersShortage),
        actions: [
          BlIconButton(
            icon: Icons.share_outlined,
            label: s.shortageShare,
            onPressed: () async {
              final text = await services.orders.shortageText();
              await sendOrderText(text);
            },
          ),
          if (services.can(Permission.purchases))
            BlIconButton(
              icon: Icons.playlist_add_check,
              label: s.ordersReorder,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReorderScreen()),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: list.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(shortageProvider),
          ),
          data: (entries) => entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: Icons.star_border,
                    title: s.shortageEmpty,
                    message: s.shortageEmptyHint,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  children: [
                    for (final e in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: _EntryTile(entry: e),
                      ),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(showShortageSheet(context)),
        icon: const Icon(Icons.add),
        // Short, so it fits beside the list on a small phone at 200%.
        label: Text(s.shortageWrite),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});

  final ShortageEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final e = entry;
    return BlCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    e.name,
                    if (e.qty != null)
                      '${e.qty!.display}${e.unitCode == null ? '' : ' ${e.unitCode}'}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (e.note != null)
                  Text(e.note!, style: TextStyle(fontSize: 13, color: t.ink)),
                Text(
                  [?e.addedBy, e.addedOn.value].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ],
            ),
          ),
          BlButton(
            label: s.shortageClear,
            icon: Icons.check,
            kind: BlButtonKind.ghost,
            onPressed: () async {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              await ref.read(appServicesProvider).orders.clearShortage([e.id]);
              container.bumpRefresh();
            },
          ),
        ],
      ),
    );
  }
}

/// The "*" in the counter's bar and the items list's: writes a line on the
/// shortage list without leaving the screen.
class ShortageButton extends ConsumerWidget {
  const ShortageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    if (!services.orders.canNoteShortage) return const SizedBox.shrink();
    return BlIconButton(
      icon: Icons.star_border,
      label: AppStrings.of(context).shortageAdd,
      onPressed: () => unawaited(showShortageSheet(context)),
    );
  }
}

/// Writes one line on the shortage list: an item found by name, or the
/// customer's own words when it is nothing the shop keeps.
Future<void> showShortageSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ShortageSheet(),
    );

class _ShortageSheet extends ConsumerStatefulWidget {
  const _ShortageSheet();

  @override
  ConsumerState<_ShortageSheet> createState() => _ShortageSheetState();
}

class _ShortageSheetState extends ConsumerState<_ShortageSheet> {
  final _what = TextEditingController();
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
    _what.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onWhat(String value) {
    _debounce?.cancel();
    setState(() {
      _item = null;
      _failure = null;
    });
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final name = _item?.name ?? _what.text.trim();
    if (name.isEmpty) {
      setState(() => _failure = s.shortageWhatNeeded);
      return;
    }
    final qtyText = _qty.text.trim();
    final qty = qtyText.isEmpty ? null : Qty.tryParse(qtyText);
    if (qtyText.isNotEmpty && (qty == null || !qty.isPositive)) {
      setState(() => _failure = s.orderItemNeeds);
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
      await ref
          .read(appServicesProvider)
          .orders
          .noteShortage(
            ShortageDraft(
              name: name,
              itemId: _item?.id,
              qty: qty,
              unitCode: qty == null ? null : _item?.unitCode,
              note: _note.text,
            ),
          );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.shortageSaved(name))));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is OrderRefused ? error.reason : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final item = _item;
    final matches = _query.isEmpty || item != null
        ? const <ItemSummary>[]
        : (ref.watch(itemSearchProvider(_query)).valueOrNull ?? const [])
              .take(5)
              .toList();

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.shortageAdd,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          if (item == null) ...[
            BlField(
              controller: _what,
              label: s.shortageWhat,
              autofocus: true,
              onChanged: _onWhat,
              prefix: const Icon(Icons.search, size: 20),
            ),
            for (final m in matches)
              ListTile(
                title: Text(m.name),
                subtitle: Text('${m.stockOnHand.display} ${m.unitCode}'),
                onTap: () => setState(() => _item = m),
              ),
          ] else
            BlCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                  ),
                  BlIconButton(
                    icon: Icons.close,
                    label: s.actionClose,
                    onPressed: () => setState(() => _item = null),
                  ),
                ],
              ),
            ),
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _qty,
            label: item == null
                ? s.shortageQty
                : '${s.shortageQty} (${item.unitCode})',
            numeric: true,
            decimals: 3,
          ),
          const SizedBox(height: BlTokens.space2),
          BlField(controller: _note, label: s.orderNote),
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.shortageSave,
            icon: Icons.star,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
