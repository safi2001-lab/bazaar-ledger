import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../attachments/attachment_strip.dart'; // M60
import '../mobile/qist_plans_screen.dart'; // M50
import '../parties/party_editor.dart';
import '../recurring/repeat_entry.dart'; // M63
import '../sales/receipt_screen.dart';
import 'charge_sheet.dart';
import 'due_chip.dart';
import 'entry_actions.dart';
import 'goods_given.dart';
import 'khata_providers.dart';
import 'opening_balance_sheet.dart';
import 'pay_supplier_sheet.dart';
import 'payables_section.dart';
import 'payment_sheet.dart';
import 'promise_sheet.dart';
import 'receive_payment_sheet.dart';
import 'send_reminder.dart';
import 'statement.dart';
import 'udhaar_providers.dart';
import 'write_off_sheet.dart';

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

    // A customer who asked not to be messaged is not offered a reminder
    // (M39); the balance card says so instead.
    final optedOut =
        ref.watch(reminderPrefsProvider(party.id)).valueOrNull?.optedOut ??
        false;

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
          if (current.balance.isPositive && !optedOut)
            BlIconButton(
              icon: Icons.chat_outlined,
              label: s.khataRemind,
              onPressed: () => unawaited(_remind(context, ref, current)),
            ),
          // Given up on as a bad debt (M44): whoever may put the books right.
          if (receivable &&
              current.balance.isPositive &&
              ref.read(appServicesProvider).udhaar.mayWriteOffNow)
            BlIconButton(
              icon: Icons.money_off_outlined,
              label: s.khataWriteOff,
              onPressed: () =>
                  unawaited(showWriteOffSheet(context, party: current)),
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
            if (receivable) RecurringOnKhata(partyId: current.id), // M63
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
    // When each open bill falls due (M38), matched to the bills by id. Read
    // beside the bills rather than instead of them, so the list the
    // payment preview is drawn from stays the writer's own.
    final due = {
      for (final b
          in ref.watch(billsDueProvider(current.id)).valueOrNull ??
              const <BillDue>[])
        b.documentId: b,
    };
    final creditDays = ref.watch(creditDaysProvider(current.id)).valueOrNull;
    return [
      _BalanceCard(party: current),
      const SizedBox(height: BlTokens.space3),
      // What they said they would pay, and when (M38).
      PromiseCard(party: current),
      const SizedBox(height: BlTokens.space3),
      // Goods given and not yet billed, rate-later ones first among them
      // (M55): shown apart from the balance, never added to it.
      GoodsGivenCard(party: current),
      const SizedBox(height: BlTokens.space4),
      QistPlansCard(partyId: current.id), // M50: phones on qist
      Row(
        children: [
          Expanded(
            child: Text(
              s.khataOpenBills,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.inkMuted,
              ),
            ),
          ),
          // The term every due date below is worked from, so a shopkeeper
          // surprised by one can see why.
          Text(
            creditDays == null
                ? s.khataCreditUsual(shopUsualCreditDays)
                : s.khataCreditDays(creditDays),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
        ],
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
                        // The bill as it was printed, or the charge with its
                        // reason (M31). This card used to do nothing, and
                        // named the bill by its database id.
                        onTap: () => bill.docType == 'other_income'
                            ? unawaited(
                                _openCharge(
                                  context,
                                  ref,
                                  current,
                                  bill.documentId,
                                ),
                              )
                            : _openBill(context, bill.documentId, bill.docNo),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bill.docNo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: t.ink,
                                    ),
                                  ),
                                  Text(
                                    bill.dateLocal,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                  // "Due 12 Oct", "Overdue 9 days" (M38).
                                  if (due[bill.documentId] case final d?)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: BlTokens.space1,
                                      ),
                                      child: DueChip.of(d),
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
      _History(party: current),
    ];
  }
}

/// Opens WhatsApp on this customer's chat, with the reminder already typed.
///
/// Chasing udhaar is the work a khata exists for. A shopkeeper with forty
/// names spends their evening on it, and the reason to move the book onto a
/// phone is that the phone can also send the message.
///
/// Since M39 the message is the shop's template in the customer's own
/// language, with the oldest bill, its due date and the shop's payment
/// details filled in; and once it has been handed over it goes in the
/// khata's log, with who sent it and how. The shopkeeper chose this one
/// customer and tapped Remind, so handing it over is taken as sending it;
/// the evening round asks instead.
Future<void> _remind(
  BuildContext context,
  WidgetRef ref,
  PartySummary party,
) async {
  final s = AppStrings.of(context);
  final services = ref.read(appServicesProvider);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);

  final ready = await services.udhaar.reminderFor(party.id);
  final outcome = ready == null
      ? ReminderOutcome.nothingOwed
      : await sendReminder(message: ready.message, party: ready.party);

  final channel = channelOf(outcome);
  if (ready != null && channel != null) {
    try {
      await services.udhaar.recordReminderSent(
        party.id,
        channel: channel,
        language: ready.prefs.language,
        amount: ready.party.balance,
      );
      container.bumpRefresh();
    } on PermissionDenied {
      // A role that may not keep the khata's log still sent the message;
      // the message is not taken back for want of a line in the log.
    }
  }

  final message = switch (outcome) {
    ReminderOutcome.noNumber => s.khataRemindNoPhone,
    ReminderOutcome.nothingOwed => s.khataRemindNothingOwed,
    _ => null,
  };
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// What this customer owes, or what the shop is holding for them.
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final optedOut =
        ref.watch(reminderPrefsProvider(party.id)).valueOrNull?.optedOut ??
        false;
    final lastSent = ref
        .watch(remindersSentProvider(party.id))
        .valueOrNull
        ?.firstOrNull;

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
          // They asked not to be messaged (M39): the Remind button is gone,
          // and this says why.
          if (optedOut) ...[
            const SizedBox(height: BlTokens.space2),
            BlChip(s.khataRemindOff, icon: Icons.notifications_off_outlined),
          ],
          // When the shop last asked, who asked, and how (M39): the first
          // thing to know before asking again.
          if (lastSent != null) ...[
            const SizedBox(height: BlTokens.space2),
            Text(
              remindedLine(s, lastSent, ref.watch(appServicesProvider)),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Reminded 3 days ago · Malik Sahib · WhatsApp".
String remindedLine(AppStrings s, ReminderSent sent, AppServices services) {
  final days = sent.daysAgo(services.udhaar.today);
  final when = days <= 0 ? s.remindedToday : s.remindedDaysAgo(days);
  final channel = switch (sent.channel) {
    ReminderChannel.whatsapp => s.sendWhatsAppShort,
    ReminderChannel.sms => s.reminderChannelSms,
    ReminderChannel.share => s.reminderChannelShare,
  };
  return s.remindedBy(when, sent.byName, channel);
}

/// What has happened on this khata, newest first.
///
/// The open bills above answer "what is still owed". This answers the
/// question a customer actually asks — "I paid you last week" — and every
/// line carries the number printed on the paper in their hand, because
/// without it the shopkeeper is asking them to take a date on trust.
///
/// Every line opens what it is about (M31): a bill as it was printed, a
/// payment with what it settled and who took it, a charge with its reason,
/// the opening balance to be corrected. Until then only a charge did
/// anything when tapped, and a payment keyed in wrong could not even be
/// looked at.
class _History extends ConsumerWidget {
  const _History({required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final entries = ref.watch(partyLedgerProvider(party.id));

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
                      // A return has no page of its own to open (M38): it
                      // says what came back and stays where it is.
                      onTap: entry.kind == 'return'
                          ? null
                          : () => _openEntry(context, ref, party, entry),
                      child: Row(
                        children: [
                          Icon(
                            entry.kind == 'return'
                                ? Icons.undo
                                : AllowanceKind.ofPaymentNo(entry.reference) !=
                                      null
                                ? Icons.money_off_outlined
                                : entry.isPayment
                                ? Icons.south_west
                                : Icons.north_east,
                            size: 18,
                            color: entry.isPayment || entry.kind == 'return'
                                ? t.money
                                : t.inkMuted,
                          ),
                          const SizedBox(width: BlTokens.space2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  // Written by the query in English; said
                                  // here in the shopkeeper's language.
                                  switch (entry.kind) {
                                    'opening' => s.partyOpeningBalance,
                                    'return' => s.khataReturn(entry.reference),
                                    // Let go, not paid (M44).
                                    'payment' =>
                                      switch (AllowanceKind.ofPaymentNo(
                                        entry.reference,
                                      )) {
                                        AllowanceKind.settlementDiscount =>
                                          s.allowanceDiscountLine(
                                            entry.reference,
                                          ),
                                        AllowanceKind.writeOff =>
                                          s.allowanceWriteOffLine(
                                            entry.reference,
                                          ),
                                        null => entry.reference,
                                      },
                                    _ => entry.reference,
                                  },
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

/// Opens whatever a khata line is about.
void _openEntry(
  BuildContext context,
  WidgetRef ref,
  PartySummary party,
  LedgerEntry entry,
) {
  switch (entry.kind) {
    case 'sale':
      _openBill(context, entry.id, entry.reference);
    case 'charge':
      unawaited(_openCharge(context, ref, party, entry.id));
    case 'payment' || 'bounce':
      // A bounce line carries the bounce entry's id, which opens the cheque.
      unawaited(showPaymentSheet(context, id: entry.id, party: party));
    case 'opening':
      unawaited(
        showOpeningBalanceSheet(
          context,
          partyId: party.id,
          partyName: party.name,
          current: entry.amount,
        ),
      );
  }
}

/// A sale bill, exactly as it was printed: shared, printed, returned or
/// cancelled from there, and never edited — the customer has the paper.
void _openBill(BuildContext context, String documentId, String docNo) =>
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReceiptScreen(documentId: documentId, docNo: docNo),
        ),
      ),
    );

enum _ChargeChoice { edit, takeBack }

/// A charge on the khata: what it was for, and — for whoever may put
/// entries right — correct it or take it back (M25, M31).
///
/// Taking it back keeps its fixed reason and its one confirmation, as it
/// has since M25; correcting it opens the charge sheet filled in with it.
/// A charge a payment has been taken against says so and offers neither,
/// because the payment has to be cancelled first.
Future<void> _openCharge(
  BuildContext context,
  WidgetRef ref,
  PartySummary party,
  String documentId,
) async {
  final s = AppStrings.of(context);
  final services = ref.read(appServicesProvider);
  final firm = await ref.read(firmProvider.future);
  if (firm == null) return;
  final charge = await services.queries.entryDocument(firm.id, documentId);
  if (charge == null || !context.mounted) return;
  final mayCorrect = canCorrect(ref);
  final standing = !charge.isCancelled && charge.paidBy.isEmpty;

  final choice = await showDialog<_ChargeChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${charge.docNo} · ${charge.note}'),
      content: Text(
        charge.paidBy.isNotEmpty
            ? s.entryPaidBy(charge.paidBy.join(', '))
            : mayCorrect
            ? s.chargeEntryHint(charge.total.amountOnly)
            : s.entryNotAllowed,
      ),
      actions: [
        EntryPhotosButton(owner: AttachmentOwner.document(charge.id)), // M60
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionClose),
        ),
        if (mayCorrect && standing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ChargeChoice.edit),
            child: Text(s.actionEdit),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ChargeChoice.takeBack),
            child: Text(s.chargeCancel),
          ),
        ],
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _ChargeChoice.edit:
      await showChargeSheet(context, party: party, editing: charge);
    case _ChargeChoice.takeBack:
      final messenger = ScaffoldMessenger.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      try {
        await services.corrections.cancelCharge(
          services.actorNow(),
          documentId: charge.id,
          reason: s.chargeCancelReason,
        );
        container.bumpRefresh();
        messenger.showSnackBar(SnackBar(content: Text(s.chargeCancelled)));
      } on VoidRefused catch (refused) {
        messenger.showSnackBar(SnackBar(content: Text(refused.reason)));
      }
    case null:
      break;
  }
}
