import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../recycle/put_away.dart'; // M60

final _vansProvider = FutureProvider.autoDispose<List<VanView>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.vans(firm.id);
});

final _hereProvider = FutureProvider.autoDispose<String>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).counterLocation();
});

final _vanDayProvider = FutureProvider.autoDispose.family<VanDay, String>((
  ref,
  vanId,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) {
    return const VanDay(salesCount: 0, expectedCash: Money.zero, stock: []);
  }
  return services.queries.vanDay(
    firm.id,
    vanId,
    BusinessDate.now(services.clock),
  );
});

String _reason(Object e) => switch (e) {
  VanRefused(:final reason) => reason,
  StockRefused(:final reason) => reason,
  PermissionDenied(:final reason) => reason,
  _ => '$e',
};

/// The shop's delivery vans, and which one this phone sells from (M18).
class VansScreen extends ConsumerWidget {
  const VansScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final services = ref.read(appServicesProvider);
      await services.vans.addVan(services.actorNow(), name: name);
      container.bumpRefresh();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_reason(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final vans = ref.watch(_vansProvider).valueOrNull ?? const [];
    final here = ref.watch(_hereProvider).valueOrNull ?? 'MAIN';

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.vansTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_add(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(s.vansNew),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space4,
            BlTokens.space4,
            BlTokens.space10 * 2,
          ),
          children: [
            Text(
              s.vansThisPhone,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            DropdownButton<String>(
              key: const ValueKey('this-phone'),
              isExpanded: true,
              value: here,
              items: [
                DropdownMenuItem(value: 'MAIN', child: Text(s.vansShopFloor)),
                for (final v in vans)
                  DropdownMenuItem(value: v.locationCode, child: Text(v.name)),
                if (here != 'MAIN' && !vans.any((v) => v.locationCode == here))
                  DropdownMenuItem(value: here, child: Text(here)),
              ],
              onChanged: !services.can(Permission.settings)
                  ? null
                  : (code) async {
                      if (code == null) return;
                      final container = ProviderScope.containerOf(
                        context,
                        listen: false,
                      );
                      await services.setCounterLocation(code);
                      container.bumpRefresh();
                    },
            ),
            const SizedBox(height: BlTokens.space4),
            if (vans.isEmpty)
              BlEmpty(icon: Icons.local_shipping_outlined, title: s.vansEmpty),
            for (final v in vans)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: BlCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => VanScreen(van: v)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: t.inkMuted),
                      const SizedBox(width: BlTokens.space3),
                      Expanded(
                        child: Text(
                          v.name,
                          style: TextStyle(fontSize: 16, color: t.ink),
                        ),
                      ),
                      Text(
                        v.locationCode,
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One van: what it sold today, what is still on it, loading it, and
/// settling the rider's cash.
class VanScreen extends ConsumerWidget {
  const VanScreen({required this.van, super.key});

  final VanView van;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final day = ref.watch(_vanDayProvider(van.id)).valueOrNull;

    void sheet(Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(van.name), actions: [PutVanAwayButton(van: van)]), // M60
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.vansToday('${day?.salesCount ?? 0}'),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  BlMoney(
                    day?.expectedCash ?? Money.zero,
                    size: 22,
                    withSymbol: true,
                  ),
                  if (day?.settled case final done?)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space2),
                      child: BlChip(
                        s.vansSettled(done.counted.toString()),
                        tone: done.difference.isZero
                            ? BlChipTone.good
                            : BlChipTone.warn,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlButton(
                    label: s.vansLoad,
                    icon: Icons.upload_outlined,
                    kind: BlButtonKind.secondary,
                    onPressed: () => sheet(_LoadSheet(van: van)),
                  ),
                ),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: BlButton(
                    label: s.vansSettle,
                    icon: Icons.point_of_sale_outlined,
                    onPressed: day?.settled != null
                        ? null
                        : () => sheet(_SettleSheet(van: van, day: day)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space4),
            BlSectionHeader(s.vansOnBoard),
            const SizedBox(height: BlTokens.space2),
            for (final line in day?.stock ?? const <VanStock>[])
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space1),
                child: BlCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.name,
                          style: TextStyle(fontSize: 15, color: t.ink),
                        ),
                      ),
                      Text(
                        '${line.qty.display} ${line.unitCode}',
                        style: TextStyle(fontSize: 15, color: t.ink),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadSheet extends ConsumerStatefulWidget {
  const _LoadSheet({required this.van});

  final VanView van;

  @override
  ConsumerState<_LoadSheet> createState() => _LoadSheetState();
}

class _LoadSheetState extends ConsumerState<_LoadSheet> {
  final _qty = TextEditingController();
  String? _itemId;
  List<ItemSummary> _items = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      if (firm == null) return;
      final items = await services.queries.searchItems(firm.id, limit: 1000);
      if (mounted) {
        setState(
          () => _items = [
            for (final i in items)
              if (i.tracksStock) i,
          ],
        );
      }
    }());
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final itemId = _itemId;
    final qty = Qty.tryParse(_qty.text);
    if (itemId == null || qty == null || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      await services.catalogue.transferStock(
        services.actorNow(),
        StockTransferDraft(
          itemId: itemId,
          qty: qty,
          from: 'MAIN',
          to: widget.van.locationCode,
        ),
      );
      container.bumpRefresh();
      navigator.pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reason(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space4,
        BlTokens.space4,
        MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButton<String>(
            key: const ValueKey('load-item'),
            isExpanded: true,
            value: _itemId,
            hint: Text(s.recipesPickItem),
            items: [
              for (final i in _items)
                DropdownMenuItem(value: i.id, child: Text(i.name)),
            ],
            onChanged: (v) => setState(() => _itemId = v),
          ),
          BlField(controller: _qty, label: s.vansQty, numeric: true),
          if (_error case final error?)
            Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.vansLoad,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_load()),
          ),
        ],
      ),
    );
  }
}

class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({required this.van, required this.day});

  final VanView van;
  final VanDay? day;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  final _counted = TextEditingController();
  bool _returnStock = true;

  /// The rider came back after the day was closed (M27).
  bool _yesterday = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  Future<void> _settle() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      final done = await services.vans.settle(
        services.actorNow(),
        widget.van.id,
        counted: Money.tryParse(_counted.text) ?? Money.zero,
        returnStock: _returnStock,
        day: _yesterday ? BusinessDate.now(services.clock).addDays(-1) : null,
      );
      container.bumpRefresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            done.difference.isZero
                ? s.vansSettledEven
                : done.difference.isNegative
                ? s.vansSettledShort(done.difference.abs.toString())
                : s.vansSettledOver(done.difference.toString()),
          ),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reason(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space4,
        BlTokens.space4,
        MediaQuery.viewInsetsOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.vansExpected,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          if (!_yesterday)
            BlMoney(
              widget.day?.expectedCash ?? Money.zero,
              size: 22,
              withSymbol: true,
            ),
          SwitchListTile.adaptive(
            value: _yesterday,
            onChanged: (v) => setState(() => _yesterday = v),
            contentPadding: EdgeInsets.zero,
            title: Text(s.vansSettleYesterday),
          ),
          const SizedBox(height: BlTokens.space3),
          BlField(controller: _counted, label: s.vansCounted, numeric: true),
          SwitchListTile.adaptive(
            value: _returnStock,
            onChanged: (v) => setState(() => _returnStock = v),
            contentPadding: EdgeInsets.zero,
            title: Text(s.vansReturnUnsold),
          ),
          if (_error case final error?)
            Text(error, style: TextStyle(color: t.danger, fontSize: 14)),
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.vansSettle,
            icon: Icons.check,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_settle()),
          ),
        ],
      ),
    );
  }
}

/// Asks for a van's name. Owns its field, so the field outlives the
/// dialog's closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.vansNew),
      content: BlField(controller: _name, label: s.vansName),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: Text(s.vansAdd),
        ),
      ],
    );
  }
}
