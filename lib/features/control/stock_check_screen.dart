import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'control_providers.dart';

/// The random stock check (M68): today's few items, counted on the shelf,
/// the differences shown, and posted on the owner's word; then every check
/// so far and what they found month by month.
///
/// A count is kept the moment it is typed and saved, against what the
/// books said at that moment, so a phone killed half way through loses
/// nothing. What a difference is worth is shown only to whoever may see
/// costs: the counter boy counts, the owner reads the rupees.
class StockCheckScreen extends ConsumerStatefulWidget {
  const StockCheckScreen({super.key});

  @override
  ConsumerState<StockCheckScreen> createState() => _StockCheckScreenState();
}

class _StockCheckScreenState extends ConsumerState<StockCheckScreen> {
  final Map<String, TextEditingController> _counts = {};
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(String itemId) =>
      _counts.putIfAbsent(itemId, TextEditingController.new);

  Future<void> _run(Future<void> Function(StockCheckServices s) act) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await act(ref.read(appServicesProvider).stockChecks);
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
    } on ApprovalNeeded {
      // The owner was not there, or backed out: nothing was posted.
      if (mounted) setState(() => _busy = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is PermissionDenied ? error.reason : '$error';
        });
      }
    }
  }

  Future<void> _keepCounts(StockCheck check) => _run((checks) async {
    for (final line in check.lines) {
      final text = _counts[line.itemId]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final qty = Qty.tryParse(text);
      if (qty == null) continue;
      await checks.count(check.id, line.itemId, qty);
      _counts[line.itemId]!.clear();
    }
  });

  Future<void> _drop(StockCheck check) async {
    final s = AppStrings.of(context);
    final reason = TextEditingController();
    final why = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.stockCheckDrop),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: InputDecoration(labelText: s.stockCheckReasonLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reason.text),
            child: Text(s.stockCheckDrop),
          ),
        ],
      ),
    );
    reason.dispose();
    if (why == null || why.trim().isEmpty || !mounted) return;
    await _run((checks) => checks.drop(check.id, why));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final today = ref.watch(stockCheckTodayProvider);
    final history = ref.watch(stockCheckHistoryProvider).valueOrNull ?? [];
    final months = shrinkageByMonth(history);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.stockCheckTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
          ),
          children: [
            Text(
              s.stockCheckIntro,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            today.when(
              loading: () => const BlSkeletonList(rows: 3),
              error: (error, _) =>
                  Text('$error', style: TextStyle(color: t.danger)),
              data: (check) => check == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.stockCheckNone,
                          style: TextStyle(fontSize: 14, color: t.ink),
                        ),
                        const SizedBox(height: BlTokens.space2),
                        if (services.stockChecks.mayCount)
                          BlButton(
                            label: s.stockCheckPick,
                            icon: Icons.shuffle,
                            busy: _busy,
                            onPressed: _busy
                                ? null
                                : () => unawaited(
                                    _run((checks) async => checks.pick()),
                                  ),
                          ),
                      ],
                    )
                  : _CheckCard(
                      check: check,
                      field: _field,
                      busy: _busy,
                      onKeep: () => unawaited(_keepCounts(check)),
                      onPost: () => unawaited(
                        _run((checks) async => checks.post(check.id)),
                      ),
                      onDrop: () => unawaited(_drop(check)),
                    ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_failure!, style: TextStyle(fontSize: 13, color: t.danger)),
            ],
            if (months.isNotEmpty && services.stockChecks.seesValue) ...[
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.stockCheckShrinkage),
              const SizedBox(height: BlTokens.space2),
              for (final m in months)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space1),
                  child: Text(
                    s.stockCheckShrinkLine(
                      m.month,
                      m.short.amountOnly,
                      m.over.amountOnly,
                      m.net.amountOnly,
                      m.checks,
                    ),
                    style: TextStyle(fontSize: 13, color: t.ink),
                  ),
                ),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.stockCheckHistory),
              const SizedBox(height: BlTokens.space2),
              for (final c in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${s.stockCheckOf(shortDate(c.date.value))} - '
                          '${s.stockCheckItems(c.lines.length)}',
                          style: TextStyle(fontSize: 13, color: t.ink),
                        ),
                      ),
                      const SizedBox(width: BlTokens.space2),
                      Flexible(
                        child: BlChip(
                          stockCheckStatusText(s, c.status),
                          tone: switch (c.status) {
                            StockCheckStatus.posted => BlChipTone.good,
                            StockCheckStatus.dropped => BlChipTone.bad,
                            _ => BlChipTone.warn,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's check: each item, its count or a box to count it in, and the
/// owner's button once every item is counted.
class _CheckCard extends ConsumerWidget {
  const _CheckCard({
    required this.check,
    required this.field,
    required this.busy,
    required this.onKeep,
    required this.onPost,
    required this.onDrop,
  });

  final StockCheck check;
  final TextEditingController Function(String itemId) field;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onPost;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final checks = ref.watch(appServicesProvider).stockChecks;
    final values = checks.seesValue && check.differing.isNotEmpty
        ? ref.watch(_valuesProvider(check)).valueOrNull
        : null;

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.stockCheckOf(shortDate(check.date.value)),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            stockCheckStatusText(s, check.status),
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          for (final line in check.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${line.name} (${line.unitCode})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  if (line.isCounted) ...[
                    Text(
                      '${s.stockCheckShelf}: ${line.counted!.display} - '
                      '${s.stockCheckBooks(line.book!.display)}',
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    if (!line.difference!.isZero)
                      Text(
                        switch (values?[line.itemId]) {
                          final value? => s.stockCheckDiffValue(
                            line.difference!.display,
                            value.amountOnly,
                          ),
                          null => s.stockCheckDiff(line.difference!.display),
                        },
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: line.difference!.isNegative
                              ? t.danger
                              : t.money,
                        ),
                      ),
                  ] else if (check.isOpen)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space1),
                      child: BlField(
                        controller: field(line.itemId),
                        label: s.stockCheckShelf,
                        numeric: true,
                        decimals: 3,
                      ),
                    ),
                ],
              ),
            ),
          if (check.isOpen && !check.allCounted)
            BlButton(
              label: s.stockCheckKeep,
              icon: Icons.check,
              busy: busy,
              onPressed: busy ? null : onKeep,
            ),
          if (check.status == StockCheckStatus.counted)
            BlButton(
              label: s.stockCheckPost,
              icon: Icons.verified_outlined,
              busy: busy,
              onPressed: busy ? null : onPost,
            ),
          if (check.isOpen) ...[
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.stockCheckDrop,
              kind: BlButtonKind.ghost,
              onPressed: busy ? null : onDrop,
            ),
          ],
        ],
      ),
    );
  }
}

/// What each difference on a check is worth, for whoever may see costs.
final _valuesProvider = FutureProvider.autoDispose
    .family<Map<String, Money>, StockCheck>((ref, check) {
      return ref.watch(appServicesProvider).stockChecks.differenceValues(check);
    });
