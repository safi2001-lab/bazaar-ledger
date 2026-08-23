import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../parties/party_editor.dart';
import 'khata_providers.dart';
import 'receive_payment_sheet.dart';

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
    final live = ref
        .watch(partySearchProvider(''))
        .valueOrNull
        ?.where((p) => p.id == party.id)
        .firstOrNull;
    final current = live ?? party;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(current.name),
        actions: [
          BlIconButton(
            icon: Icons.edit_outlined,
            label: s.khataDetails,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PartyEditorScreen(party: current),
              ),
            ),
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
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: BlCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            unawaited(showReceivePaymentSheet(context, party: current)),
        icon: const Icon(Icons.payments_outlined),
        label: Text(s.khataReceive),
      ),
    );
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
        ],
      ),
    );
  }
}
