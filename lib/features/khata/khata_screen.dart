import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_editor.dart';
import 'charge_sheet.dart';
import 'khata_providers.dart';
import 'pay_supplier_sheet.dart';
import 'payables_section.dart';
import 'receive_payment_sheet.dart';
import 'send_reminder.dart';
import 'statement.dart';

/// One customer's khata: what they owe, on which bills, and a way to take it.
///
/// Tapping a customer used to open the editor — a form for their phone number
/// and their credit limit. That is the second thing a shopkeeper wants from a
/// name in a khata. The first is *how much*, and the thing they actually do
/// next is take money off it.
///
/// So the tap lands here, and editing is an action on this screen rather than
/// the destination.
class KhataScreen extends ConsumerWidget {
  const KhataScreen({super.key, required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bills = ref.watch(openBillsProvider(party.id));

    // Re-read rather than trusting what was passed in: the caller's copy was
    // fetched when its list was drawn, and a payment taken here changes it.
    final current = ref.watch(partyProvider(party.id)).valueOrNull ?? party;

    // A supplier's khata is what the shop owes them; a customer's is what
    // they owe the shop. A party who is both gets both, each against its own
    // bills, and never one netted figure neither side agreed to.
    final receivable = current.isCustomer;
    final payable = current.isSupplier;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(current.name),
        actions: [
          // The account on paper, to hand them or send them (M24).
          BlIconButton(
            icon: Icons.picture_as_pdf_outlined,
            label: s.statementShare,
            onPressed: () => unawaited(
              shareStatement(context, ref, current, owedToUs: receivable),
            ),
          ),
          if (current.balance.isPositive)
            BlIconButton(
              icon: Icons.chat_outlined,
              label: s.khataRemind,
              onPressed: () =>
                  unawaited(_remind(context, ref, current, bills.valueOrNull)),
            ),
          // A charge with no sale behind it: a bank's bounce fee, a
          // transporter's fare.
          if (receivable)
            BlIconButton(
              icon: Icons.post_add_outlined,
              label: s.chargeTitle,
              onPressed: () =>
                  unawaited(showChargeSheet(context, party: current)),
            ),
          BlIconButton(
            icon: Icons.edit_outlined,
            label: s.khataDetails,
            onPressed: () async {
              final archived = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => PartyEditorScreen(party: current),
                ),
              );
              // Hidden from the khata: nothing left to show here.
              if ((archived ?? false) && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            BlTokens.space10 * 2,
          ),
          children: [
            if (receivable) ..._receivable(context, ref, current, bills),
            if (receivable && payable) const SizedBox(height: BlTokens.space5),
            if (payable)
              PayablesSection(
                party: current,
                showHistory: !receivable,
                // The floating button receives when this is also a customer,
                // so paying needs a button of its own.
                offerPay: receivable,
              ),
          ],
        ),
      ),
      floatingActionButton: receivable
          ? FloatingActionButton.extended(
              onPressed: () =>
                  unawaited(showReceivePaymentSheet(context, party: current)),
              icon: const Icon(Icons.payments_outlined),
              label: Text(s.khataReceive),
            )
          : current.payable.isPositive
          ? FloatingActionButton.extended(
              onPressed: () =>
                  unawaited(showPaySupplierSheet(context, party: current)),
              icon: const Icon(Icons.outbound_outlined),
              label: Text(s.khataPay),
            )
          : null,
    );
  }

  /// What this customer owes, on which bills, and what has moved it.
  List<Widget> _receivable(
    BuildContext context,
    WidgetRef ref,
    PartySummary current,
    AsyncValue<List<OpenBill>> bills,
  ) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return [
      _BalanceCard(party: current),
      const SizedBox(height: BlTokens.space4),
      Text(
        s.khataOpenBills,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: t.inkMuted,
        ),
      ),
      const SizedBox(height: BlTokens.space2),
      bills.when(
        loading: () => const BlSkeletonList(rows: 3),
        error: (error, _) => BlError(
          title: s.commonSomethingWentWrong,
          message: '$error',
          retryLabel: s.actionRetry,
          onRetry: () => ref.invalidate(openBillsProvider(party.id)),
        ),
        data: (rows) => rows.isEmpty
            ? BlEmpty(
                icon: Icons.check_circle_outline,
                title: s.khataNoBills,
                message: s.khataNoBillsHint,
              )
            : Column(
                children: [
                  for (final bill in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: BlCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bill.dateLocal,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: t.ink,
                                    ),
                                  ),
                                  Text(
                                    bill.documentId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                ],
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
      const SizedBox(height: BlTokens.space5),
      Text(
        s.khataHistory,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: t.inkMuted,
        ),
      ),
      const SizedBox(height: BlTokens.space2),
      _History(partyId: party.id),
    ];
  }
}

/// Opens WhatsApp on this customer's chat, with the reminder already typed.
///
/// Chasing udhaar is the work a khata exists for. A shopkeeper with forty
/// names spends their evening on it, and the reason to move the book onto a
/// phone is that the phone can also send the message.
Future<void> _remind(
  BuildContext context,
  WidgetRef ref,
  PartySummary party,
  List<OpenBill>? bills,
) async {
  final s = AppStrings.of(context);
  final firm = ref.read(firmProvider).valueOrNull;
  if (firm == null) return;

  final outcome = await sendReminder(
    shopName: firm.name,
    party: party,
    // Oldest first already, so the first is the one the customer has been
    // sitting on. "Since June" is what makes a reminder land.
    oldestBillDate: (bills ?? const []).firstOrNull?.dateLocal,
  );

  if (!context.mounted) return;
  final message = switch (outcome) {
    ReminderOutcome.noNumber => s.khataRemindNoPhone,
    ReminderOutcome.nothingOwed => s.khataRemindNothingOwed,
    _ => null,
  };
  if (message != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// What this customer owes, or what the shop is holding for them.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    // A negative balance is money the shop is holding, not a debt that has
    // gone the wrong way, and it is labelled as such. "Owes −2,000" is a
    // sentence a shopkeeper has to translate in their head at the counter.
    final inCredit = party.balance.isNegative;

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            inCredit ? s.khataAdvance : s.khataBalance,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space1),
          BlMoney(
            inCredit ? party.balance.abs : party.balance,
            size: 30,
            withSymbol: true,
          ),
          if (party.isOverCreditLimit) ...[
            const SizedBox(height: BlTokens.space2),
            BlChip(
              s.khataCreditLimitOver,
              tone: BlChipTone.bad,
              icon: Icons.warning_amber_outlined,
            ),
          ],
          // Kept after the money is paid back, and quieter then: a customer
          // whose cheques bounce is worth knowing about the next time one is
          // offered.
          if (party.bouncedCheques > 0) ...[
            const SizedBox(height: BlTokens.space2),
            BlChip(
              s.khataChequeBounced(party.bouncedCheques),
              tone: party.hasUnsettledBounce ? BlChipTone.bad : BlChipTone.warn,
              icon: Icons.report_gmailerrorred_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

/// What has happened on this khata, newest first.
///
/// The open bills above answer "what is still owed". This answers the
/// question a customer actually asks — "I paid you last week" — and every
/// line carries the number printed on the paper in their hand, because
/// without it the shopkeeper is asking them to take a date on trust.
class _History extends ConsumerWidget {
  const _History({required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final entries = ref.watch(partyLedgerProvider(partyId));

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
                      child: Row(
                        children: [
                          Icon(
                            entry.isPayment
                                ? Icons.south_west
                                : Icons.north_east,
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
