import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'when.dart';

final _historyProvider = FutureProvider.autoDispose
    .family<List<HistoryEvent>, RecordRef>((ref, record) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).audit.history(record);
    });

/// Opens [record]'s history, titled with [label]: the bill's number, the
/// customer's name.
Future<void> openHistory(
  BuildContext context, {
  required RecordRef record,
  required String label,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => HistoryScreen(record: record, label: label),
  ),
);

/// "Tareekh": the action that opens a record's history (M42).
///
/// One line on any record's page: a bill, a payment, an expense, a
/// customer, an item. Shown only to a role that may read the activity log
/// — a cashier asking who cancelled a bill is asking the owner's question —
/// and the service refuses anyone else anyway.
///
/// ```dart
/// HistoryButton(record: RecordRef.document(documentId), label: docNo),
/// ```
class HistoryButton extends ConsumerWidget {
  /// An icon for an app bar.
  const HistoryButton({super.key, required this.record, required this.label})
    : wide = false;

  /// A full-width button, for a page laid out as a column of them.
  const HistoryButton.wide({
    super.key,
    required this.record,
    required this.label,
  }) : wide = true;

  final RecordRef record;
  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appServicesProvider).can(Permission.audit)) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    void open() =>
        unawaited(openHistory(context, record: record, label: label));
    if (!wide) {
      return BlIconButton(
        icon: Icons.history,
        label: s.trailAction,
        onPressed: open,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: BlButton(
        label: s.trailAction,
        icon: Icons.history,
        kind: BlButtonKind.ghost,
        onPressed: open,
      ),
    );
  }
}

/// Everything that happened to one record, in the order it happened.
///
/// Oldest first, because it is read as a story: made, printed, a receipt
/// against it, goods back, cancelled — and why. Each line says who, on
/// which counter and when; an edit says what each field was and became; a
/// line about another paper (the return, the receipt, the corrected entry)
/// opens that paper's own history.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, required this.record, required this.label});

  final RecordRef record;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final events = ref.watch(_historyProvider(record));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.trailTitle(label))),
      body: SafeArea(
        child: events.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Center(
                  child: BlEmpty(icon: Icons.history, title: s.trailEmpty),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: _EventCard(event: rows[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final HistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final e = event;
    final colour = switch (e.kind) {
      HistoryKind.cancelled => t.danger,
      HistoryKind.approved => t.warning,
      HistoryKind.paid => t.money,
      _ => t.inkMuted,
    };
    final linked = e.linked;
    final label = e.linkedLabel;
    final opens = linked != null && RecordRef.supports(linked.table);
    final when = shopTime(e.atUtcMillis);

    return BlCard(
      onTap: opens
          ? () => unawaited(
              openHistory(context, record: linked, label: label ?? ''),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(e), size: 20, color: colour),
          const SizedBox(width: BlTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label == null || label.isEmpty
                      ? _title(s, e)
                      : '${_title(s, e)} · $label',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (e.summary case final summary? when summary != label)
                  Text(summary, style: TextStyle(fontSize: 13, color: t.ink)),
                for (final c in e.changes)
                  Text(
                    '${_field(s, c.field)}: ${_value(s, c.field, c.before)} '
                    '→ ${_value(s, c.field, c.after)}',
                    style: TextStyle(fontSize: 13, color: t.ink),
                  ),
                if (e.reason case final why?)
                  Text(
                    s.trailWhy(why),
                    style: TextStyle(
                      fontSize: 13,
                      color: e.kind == HistoryKind.cancelled
                          ? t.danger
                          : t.inkMuted,
                    ),
                  ),
                const SizedBox(height: BlTokens.space1),
                Text(
                  e.device == null
                      ? s.trailBy(e.who, when)
                      : s.trailByOn(e.who, e.device!, when),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ],
            ),
          ),
          if (e.amount case final amount?) ...[
            const SizedBox(width: BlTokens.space2),
            BlMoney(amount, size: 14),
          ],
          if (opens) Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
        ],
      ),
    );
  }

  static IconData _icon(HistoryEvent e) => switch (e.kind) {
    HistoryKind.created => Icons.add_circle_outline,
    HistoryKind.printed =>
      e.actionCode == 'PRINTED' ? Icons.print_outlined : Icons.print_disabled,
    HistoryKind.changed => Icons.edit_outlined,
    HistoryKind.cancelled => Icons.block,
    HistoryKind.returned => Icons.assignment_return_outlined,
    HistoryKind.paid => Icons.payments_outlined,
    HistoryKind.corrected => Icons.published_with_changes,
    HistoryKind.approved => Icons.lock_open_outlined,
    HistoryKind.other => Icons.history,
  };

  /// What happened, in the shop's language. The log's own line, in
  /// English as it was written at the time, is shown beneath it.
  static String _title(AppStrings s, HistoryEvent e) => switch (e.actionCode) {
    'PRINTED' => s.trailPrinted,
    'PRINT_FAILED' || 'PRINT_PARTIAL' || 'PRINT_UNKNOWN' => s.trailPrintFailed,
    'PAID_AT_COUNTER' => s.trailPaidAtCounter,
    'LET_GO_AGAINST' => s.trailLetGo,
    'PAID_AGAINST' => s.trailPaid,
    'SETTLED_BILL' => s.trailSettled,
    'SETTLED_BILL_RELEASED' => s.trailReleased,
    'CONVERTED_FROM' => s.trailMadeFrom,
    'CONVERTED_TO' => s.trailBecame,
    'RETURN_OF' => s.trailReturnOf,
    'RETURNED_AGAINST' => s.trailReturned,
    _ => switch (e.kind) {
      HistoryKind.created => s.trailMade,
      HistoryKind.printed => s.trailPrinted,
      HistoryKind.changed => s.trailChanged,
      HistoryKind.cancelled => s.trailCancelled,
      HistoryKind.returned => s.trailReturned,
      HistoryKind.paid => s.trailPaid,
      HistoryKind.corrected => s.trailCorrected,
      HistoryKind.approved => s.trailApproved,
      HistoryKind.other => e.summary ?? e.actionCode,
    },
  };

  static String _field(AppStrings s, String key) => switch (key) {
    'name' => s.trailFieldName,
    'phone' => s.trailFieldPhone,
    'address' => s.trailFieldAddress,
    'sale_rate_milli_paisa' => s.trailFieldSaleRate,
    'purchase_rate_milli_paisa' => s.trailFieldPurchaseRate,
    'credit_limit_paisa' => s.trailFieldCreditLimit,
    'opening_balance_paisa' => s.trailFieldOpening,
    'amount_paisa' => s.trailFieldAmount,
    'is_active' => s.trailFieldActive,
    'party_group' => s.trailFieldGroup,
    'barcode' => s.trailFieldBarcode,
    _ =>
      key
          .replaceAll(RegExp(r'_(milli_paisa|paisa|thousandths|bp)$'), '')
          .replaceAll('_', ' '),
  };

  /// A stored value as the shop reads it: rupees, not paisa.
  static String _value(AppStrings s, String key, Object? v) {
    if (v == null || v == '') return '—';
    if (key.startsWith('is_')) return v == 1 ? s.trailYes : s.trailNo;
    if (v is int) {
      if (key.endsWith('_milli_paisa')) return Rate.raw(v).amountOnly;
      if (key.endsWith('_paisa')) return Money.paisa(v).amountOnly;
      if (key.endsWith('_thousandths')) {
        final sign = v < 0 ? '-' : '';
        final whole = v.abs() ~/ 1000;
        final part = (v.abs() % 1000).toString().padLeft(3, '0');
        return part == '000'
            ? '$sign$whole'
            : '$sign$whole.${part.replaceAll(RegExp(r'0+$'), '')}';
      }
    }
    return '$v';
  }
}
