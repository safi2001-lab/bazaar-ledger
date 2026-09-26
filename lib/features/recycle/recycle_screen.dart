import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What the shop has hidden, and a way to bring it back.
///
/// Nothing in this app is ever deleted — six-year retention is a legal
/// obligation, and an old bill has to keep pointing at the item it sold —
/// but until this, hiding was one-way. A shopkeeper who archived the wrong
/// item, or stopped stocking one and started again, could only enter it a
/// second time: a duplicate with none of its history, and a stock count
/// split across two rows.
final archivedItemsProvider = FutureProvider.autoDispose<List<ItemSummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.archivedItems(firm.id);
});

final archivedPartiesProvider = FutureProvider.autoDispose<List<PartySummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.archivedParties(firm.id);
});

class RecycleScreen extends ConsumerWidget {
  const RecycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final items = ref.watch(archivedItemsProvider);
    final parties = ref.watch(archivedPartiesProvider);

    final everything = [...?items.valueOrNull, ...?parties.valueOrNull];
    final loaded = items.hasValue && parties.hasValue;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.recycleTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (!loaded)
              const BlSkeletonList(rows: 3)
            else if (everything.isEmpty)
              BlEmpty(icon: Icons.inventory_2_outlined, title: s.recycleEmpty)
            else ...[
              if (items.requireValue.isNotEmpty) ...[
                BlSectionHeader(s.recycleItems),
                const SizedBox(height: BlTokens.space2),
                for (final item in items.requireValue)
                  _HiddenRow(
                    name: item.name,
                    detail: item.saleRate.amountOnly,
                    restore: (actor, services) =>
                        services.catalogue.restoreItem(actor, item.id),
                  ),
                const SizedBox(height: BlTokens.space4),
              ],
              if (parties.requireValue.isNotEmpty) ...[
                BlSectionHeader(s.recycleParties),
                const SizedBox(height: BlTokens.space2),
                for (final party in parties.requireValue)
                  _HiddenRow(
                    name: party.name,
                    detail: party.phone,
                    restore: (actor, services) =>
                        services.catalogue.restoreParty(actor, party.id),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _HiddenRow extends ConsumerStatefulWidget {
  const _HiddenRow({
    required this.name,
    required this.detail,
    required this.restore,
  });

  final String name;
  final String? detail;
  final Future<void> Function(ActorContext actor, AppServices services) restore;

  @override
  ConsumerState<_HiddenRow> createState() => _HiddenRowState();
}

class _HiddenRowState extends ConsumerState<_HiddenRow> {
  bool _busy = false;

  Future<void> _bringBack() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.restore(services.actorNow(), services);
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(content: Text(s.recycleRestored(widget.name))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  if (widget.detail != null)
                    Text(
                      widget.detail!,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            BlButton(
              label: s.recycleRestore,
              icon: Icons.restore,
              kind: BlButtonKind.secondary,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_bringBack()),
            ),
          ],
        ),
      ),
    );
  }
}
