import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../expenses/expense_entry_sheet.dart';
import '../purchases/send_back_sheet.dart';
import 'khata_providers.dart';
import 'pay_supplier_sheet.dart';
import 'payment_sheet.dart';

/// What the shop owes one party, and a way to pay it.
///
/// Its own section rather than folded into the customer's balance. A mill
/// that sells the shop rice and buys its bran is owed one figure and owes
/// another, each against its own bills, and a single netted number would be
/// one neither side agreed to.
class PayablesSection extends ConsumerWidget {
  const PayablesSection({
    super.key,
    required this.party,
    required this.showHistory,
    required this.offerPay,
  });

  final PartySummary party;

  /// Whether to list what moved the payable. Off when the customer history
  /// is already on screen above, so a party who is both does not get two
  /// ledgers stacked on one page.
  final bool showHistory;

  /// Whether the card carries its own Pay button. Off when the screen's
  /// floating button already pays, so the same action is not offered twice.
  final bool offerPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bills = ref.watch(openPayablesProvider(party.id));

    final label = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: t.inkMuted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.khataPayable,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space1),
              BlMoney(party.payable, size: 30, withSymbol: true),
              if (offerPay && party.payable.isPositive) ...[
                const SizedBox(height: BlTokens.space3),
                BlButton(
                  label: s.khataPay,
                  icon: Icons.outbound_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () =>
                      unawaited(showPaySupplierSheet(context, party: party)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: BlTokens.space4),
        Text(s.khataOpenPayables, style: label),
        const SizedBox(height: BlTokens.space2),
        bills.when(
          loading: () => const BlSkeletonList(rows: 2),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(openPayablesProvider(party.id)),
          ),
          data: (rows) => rows.isEmpty
              ? BlEmpty(
                  icon: Icons.check_circle_outline,
                  title: s.khataNoPayables,
                )
              : Column(
                  children: [
                    for (final bill in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: BlCard(
                          // The delivery (to send goods back against) or the
                          // expense (to correct), by its number (M31).
                          onTap: () => _openDocument(
                            context,
                            kind: bill.docType == 'expense'
                                ? 'expense'
                                : 'purchase',
                            documentId: bill.documentId,
                            docNo: bill.docNo,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  bill.docNo.isEmpty
                                      ? bill.dateLocal
                                      : '${bill.docNo} · ${bill.dateLocal}',
                                  style: TextStyle(fontSize: 14, color: t.ink),
                                ),
                              ),
                              BlMoney(bill.outstanding, size: 16),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (showHistory) ...[
          const SizedBox(height: BlTokens.space5),
          Text(s.khataHistory, style: label),
          const SizedBox(height: BlTokens.space2),
          _PayablesHistory(party: party),
        ],
      ],
    );
  }
}

/// What moved the payable, newest first. Every line but a return opens what
/// it is about (M31): a payment to correct or cancel, an expense, or the
/// delivery to send goods back against.
class _PayablesHistory extends ConsumerWidget {
  const _PayablesHistory({required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final entries = ref.watch(payablesLedgerProvider(party.id));

    return entries.when(
      loading: () => const BlSkeletonList(rows: 3),
      error: (error, _) =>
          BlError(title: s.commonSomethingWentWrong, message: '$error'),
      data: (rows) => rows.isEmpty
          ? Text(
              s.khataHistoryEmpty,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            )
          : Column(
              children: [
                for (final entry in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: BlCard(
                      onTap: switch (entry.kind) {
                        'payment' => () => unawaited(
                          showPaymentSheet(context, id: entry.id, party: party),
                        ),
                        'purchase' || 'expense' => () => _openDocument(
                          context,
                          kind: entry.kind,
                          documentId: entry.id,
                          docNo: entry.reference,
                        ),
                        // A return to a supplier has no page of its own yet.
                        _ => null,
                      },
                      child: Row(
                        children: [
                          // Money going out points out: the reverse of the
                          // customer khata, where a payment comes in.
                          Icon(
                            entry.isPayment
                                ? Icons.north_east
                                : Icons.south_west,
                            size: 18,
                            color: entry.isPayment ? t.money : t.inkMuted,
                          ),
                          const SizedBox(width: BlTokens.space2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.reference,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, color: t.ink),
                                ),
                                Text(
                                  entry.dateLocal,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              BlMoney(entry.amount, size: 15, showSign: true),
                              BlMoney(
                                entry.balanceAfter,
                                size: 12,
                                colour: t.inkMuted,
                                weight: FontWeight.w400,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A delivery opens where goods are sent back against it, as the purchase
/// list does; an expense opens its own page.
void _openDocument(
  BuildContext context, {
  required String kind,
  required String documentId,
  required String docNo,
}) => unawaited(
  kind == 'expense'
      ? showExpenseEntrySheet(context, documentId: documentId)
      : showSendBackSheet(context, documentId: documentId, docNo: docNo),
);
