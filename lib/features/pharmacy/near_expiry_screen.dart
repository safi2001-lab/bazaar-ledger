import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../reports/report_export.dart';
import 'batch_hold_sheet.dart';
import 'pharmacy_providers.dart';

/// The near-expiry list, by supplier (M49), and the return that sends it
/// back.
///
/// Marg's answer to a chemist's oldest loss: every batch on the shop floor
/// that runs out within the month — or has already, or is on hold — listed
/// under the distributor it came from, because it is the distributor who
/// takes it back. Tick the batches, send them back: a return against each
/// delivery they came in on, every strip out of its own batch, the
/// supplier's khata credited, and a note to hand his man.
///
/// From the items list, for a shop that is a pharmacy.
class NearExpiryButton extends ConsumerWidget {
  const NearExpiryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmacy = ref.watch(firmProvider).valueOrNull?.isPharmacy ?? false;
    if (!pharmacy) return const SizedBox.shrink();
    return BlIconButton(
      icon: Icons.event_busy_outlined,
      label: AppStrings.of(context).pharmacyNearExpiryTitle,
      onPressed: () => Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const NearExpiryScreen())),
    );
  }
}

class NearExpiryScreen extends ConsumerStatefulWidget {
  const NearExpiryScreen({super.key});

  @override
  ConsumerState<NearExpiryScreen> createState() => _NearExpiryScreenState();
}

class _NearExpiryScreenState extends ConsumerState<NearExpiryScreen> {
  /// How far ahead to look. Ten years is "every batch on the shelf", so a
  /// batch that is fine but recalled can be found and held from here too.
  static const _all = 3650;
  int _days = 30;

  /// The batches ticked, by lot.
  final _picked = <String>{};
  bool _busy = false;

  Future<void> _send(SupplierExpiries group) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final batches = [
      for (final b in group.batches)
        if (_picked.contains(b.lotId)) b,
    ];
    if (batches.isEmpty || group.supplierId == null) return;
    final value = Money.sum([for (final b in batches) b.value]);
    final reason = TextEditingController(text: s.pharmacyReturnReasonDefault);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group.supplierName ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.pharmacyReturnConfirm(
                group.supplierName ?? '',
                value.amountOnly,
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: reason, label: s.pharmacyReturnReason),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.pharmacyReturnSend),
          ),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (!(yes ?? false) || !mounted) return;

    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      final done = await services.pharmacy.returnToSupplier(
        group.supplierId!,
        batches,
        reason: why.isEmpty ? s.pharmacyReturnReasonDefault : why,
      );
      _picked.removeAll([for (final b in batches) b.lotId]);
      container.bumpRefresh();
      if (!mounted) return;
      setState(() => _busy = false);
      await _showDone(group, done);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.error_outline, color: context.bl.danger),
          content: Text(error is ReturnRefused ? error.reason : '$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.of(context).actionOk),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showDone(SupplierExpiries group, ExpiryReturnDone done) {
    final s = AppStrings.of(context);
    final firm = ref.read(firmProvider).valueOrNull;
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: context.bl.money),
        title: Text(s.pharmacyReturnDone(done.returnNos.join(', '))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.pharmacyReturnCredited(done.credited.amountOnly)),
            if (done.refunded.isPositive)
              Text(s.pharmacyReturnRefunded(done.refunded.amountOnly)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(
              shareReport(
                expiryReturnNote(
                  shopName: firm?.name ?? '',
                  supplier: group.supplierName ?? '',
                  date: today,
                  done: done,
                ),
                ReportFormat.pdf,
                shopName: firm?.name ?? '',
              ),
            ),
            child: Text(s.pharmacyReturnNote),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.actionOk),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final groups = ref.watch(nearExpiryProvider(_days));
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    final mayMove = ref.read(appServicesProvider).pharmacy.canMoveBatches;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.pharmacyNearExpiryTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space3,
                BlTokens.space4,
                0,
              ),
              child: Wrap(
                spacing: BlTokens.space2,
                children: [
                  for (final days in const [30, 60, 90, 180, _all])
                    ChoiceChip(
                      selected: _days == days,
                      label: Text(
                        days == _all
                            ? s.pharmacyNearExpiryAll
                            : s.pharmacyNearExpiryDays(days),
                      ),
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
            ),
            Expanded(
              child: groups.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(),
                ),
                error: (error, _) => BlError(
                  title: s.commonSomethingWentWrong,
                  message: '$error',
                ),
                data: (list) => list.isEmpty
                    ? Center(
                        child: BlEmpty(
                          icon: Icons.event_available_outlined,
                          title: s.pharmacyNearExpiryEmpty,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(BlTokens.space4),
                        children: [
                          for (final group in list) ...[
                            BlSectionHeader(
                              '${group.supplierName ?? s.pharmacyNoSupplier}'
                              ' · Rs ${group.value.amountOnly}',
                            ),
                            const SizedBox(height: BlTokens.space2),
                            for (final b in group.batches)
                              _BatchRow(
                                batch: b,
                                today: today,
                                picked: _picked.contains(b.lotId),
                                onPick: group.supplierId == null || !mayMove
                                    ? null
                                    : (yes) => setState(
                                        () => yes
                                            ? _picked.add(b.lotId)
                                            : _picked.remove(b.lotId),
                                      ),
                                onHold: mayMove
                                    ? () => showBatchHoldSheet(
                                        context,
                                        lotId: b.lotId,
                                        lotNo: b.lotNo,
                                        itemName: b.itemName,
                                        holdReason: b.holdReason,
                                      )
                                    : null,
                              ),
                            if (group.batches.any(
                              (b) => _picked.contains(b.lotId),
                            )) ...[
                              const SizedBox(height: BlTokens.space2),
                              BlButton(
                                label: s.pharmacyReturnPicked(
                                  group.batches
                                      .where((b) => _picked.contains(b.lotId))
                                      .length,
                                ),
                                icon: Icons.assignment_return_outlined,
                                busy: _busy,
                                onPressed: _busy
                                    ? null
                                    : () => unawaited(_send(group)),
                              ),
                            ],
                            const SizedBox(height: BlTokens.space4),
                          ],
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

class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.batch,
    required this.today,
    required this.picked,
    this.onPick,
    this.onHold,
  });

  final ExpiringBatch batch;
  final BusinessDate today;
  final bool picked;
  final ValueChanged<bool>? onPick;
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final expired = batch.isExpiredOn(today);
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space1),
      child: BlCard(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space2,
          vertical: BlTokens.space2,
        ),
        child: Row(
          children: [
            Checkbox(
              value: picked,
              onChanged: onPick == null ? null : (v) => onPick!(v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batch.itemName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    '${batch.lotNo} · ${batch.qty.display} ${batch.unitCode}',
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (batch.holdReason case final reason?)
                    Text(
                      s.pharmacyHeld(reason),
                      style: TextStyle(fontSize: 12, color: t.danger),
                    ),
                ],
              ),
            ),
            if (batch.expiry case final expiry?)
              BlChip(
                expired ? s.pharmacyExpired : expiry.value,
                tone: expired ? BlChipTone.bad : BlChipTone.warn,
              ),
            if (onHold != null)
              BlIconButton(
                icon: batch.isHeld ? Icons.lock_open : Icons.block,
                label: batch.isHeld ? s.pharmacyRelease : s.pharmacyHold,
                onPressed: onHold!,
              ),
          ],
        ),
      ),
    );
  }
}
