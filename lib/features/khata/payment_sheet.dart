import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/history_screen.dart';
import '../printing/pdf_font.dart';
import '../sales/receipt_screen.dart';
import 'entry_actions.dart';
import 'khata_providers.dart';
import 'pay_supplier_sheet.dart';
import 'receive_payment_sheet.dart';

/// One payment, opened from a khata (M31).
///
/// Until this a payment in the khata's history was a line that did nothing
/// when tapped, and the question a customer actually asks about one —
/// "which bill did my Rs 5,000 go on, and who took it?" — had no answer on
/// screen. Here is the whole of it: the amount, the day, how it came, the
/// bills it went against and what was left on account, the note, and who
/// keyed it in. With three things to do: send the customer a receipt for it,
/// correct it, or cancel it.
///
/// A payment that cannot be put right says why, in words, instead of
/// offering buttons that would only be refused: money taken at the counter
/// goes with its bill, and a cheque the bank has is the bank's to decide.
///
/// [id] is the payment's own, or a bounced cheque's khata line, which opens
/// the cheque it is about. [party] is the khata it was opened from, which an
/// edit is made against.
Future<void> showPaymentSheet(
  BuildContext context, {
  required String id,
  required PartySummary party,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PaymentSheet(id: id, party: party),
);

class _PaymentSheet extends ConsumerWidget {
  const _PaymentSheet({required this.id, required this.party});

  final String id;
  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final detail = ref.watch(paymentDetailProvider(id));
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: detail.when(
        loading: () => const BlSkeletonList(rows: 4),
        error: (error, _) =>
            BlError(title: s.commonSomethingWentWrong, message: '$error'),
        data: (payment) => payment == null
            ? BlEmpty(title: s.commonNothingSaved)
            : _Body(payment: payment, party: party),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.payment, required this.party});

  final PaymentDetail payment;
  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final lock = payment.lock;
    final lockText = switch (lock) {
      PaymentLock.takenWithBill => s.entryTakenWithBill(
        payment.counterBillNo ?? '',
      ),
      PaymentLock.chequeAtBank => s.entryChequeAtBank,
      PaymentLock.chequeCleared => s.entryChequeCleared,
      PaymentLock.chequeBounced => s.entryChequeBounced,
      PaymentLock.none || PaymentLock.cancelled => null,
    };
    final mayCorrect = canCorrect(ref);
    // A settlement discount or a write-off (M44): money that did not come.
    // Titled as what it is; cancelled to put the udhaar back, never edited
    // (the edit path would take it back as money), never sent as a receipt.
    final allowance = AllowanceKind.ofPaymentNo(payment.paymentNo);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            switch (allowance) {
              AllowanceKind.settlementDiscount => s.entryDiscountTitle(
                payment.paymentNo,
              ),
              AllowanceKind.writeOff => s.entryWriteOffTitle(payment.paymentNo),
              null =>
                payment.isReceipt
                    ? s.entryReceiptTitle(payment.paymentNo)
                    : s.entryPaymentTitle(payment.paymentNo),
            },
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          if (payment.partyName case final name?)
            Text(name, style: TextStyle(fontSize: 14, color: t.inkMuted)),
          const SizedBox(height: BlTokens.space3),
          Row(
            children: [
              BlMoney(payment.amount, size: 28, withSymbol: true),
              const SizedBox(width: BlTokens.space3),
              if (payment.isCancelled)
                BlChip(
                  s.entryCancelled,
                  tone: BlChipTone.bad,
                  icon: Icons.block,
                ),
            ],
          ),
          if (payment.cancelReason case final why? when payment.isCancelled)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space1),
              child: Text(
                s.entryCancelledWhy(why),
                style: TextStyle(fontSize: 13, color: t.danger),
              ),
            ),
          if (payment.cancelledBy case final who? when payment.isCancelled)
            Text(
              s.entryCancelledBy(who, payment.cancelledAt ?? ''),
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
          const SizedBox(height: BlTokens.space3),
          EntryLine(s.entryDate, payment.dateLocal),
          EntryLine(s.entryHow, modeLabel(s, payment.mode)),
          if (payment.paymentAccountName.isNotEmpty)
            EntryLine(s.entryAccount, payment.paymentAccountName),
          if (payment.chequeNo case final no?) EntryLine(s.wasooliChequeNo, no),
          if (payment.chequeBank case final bank?)
            EntryLine(s.wasooliChequeBank, bank),
          if (payment.chequeDue case final due?)
            EntryLine(s.chequeDue, due.value),
          if (payment.reference case final reference?)
            EntryLine(s.entryReference, reference),
          if (payment.notes case final notes?)
            EntryLine(s.entryReference, notes),
          // Who keyed it in and when: the question a shop with staff asks
          // of any receipt that surprises it.
          EntryLine(
            s.entryEnteredBy,
            payment.enteredAt == null
                ? payment.enteredBy
                : '${payment.enteredBy} · ${payment.enteredAt}',
          ),
          // Everything that happened to it since, in one place (M42).
          HistoryButton.wide(
            record: RecordRef.payment(payment.id),
            label: payment.paymentNo,
          ),
          // Its history: the entry it corrected, or the one that corrected
          // it, each a tap away, so a receipt edited twice can be followed
          // back to the first one keyed in.
          if (payment.replaces case final no?)
            _Link(
              label: s.entryReplaces(no),
              onTap: payment.replacesId == null
                  ? null
                  : () => unawaited(
                      showPaymentSheet(
                        context,
                        id: payment.replacesId!,
                        party: party,
                      ),
                    ),
            ),
          if (payment.replacedBy case final no?)
            _Link(
              label: s.entryReplacedBy(no),
              onTap: payment.replacedById == null
                  ? null
                  : () => unawaited(
                      showPaymentSheet(
                        context,
                        id: payment.replacedById!,
                        party: party,
                      ),
                    ),
            ),
          if (payment.settled.isNotEmpty ||
              (payment.isReceipt && payment.onAccount.isPositive)) ...[
            const SizedBox(height: BlTokens.space3),
            Text(
              s.entrySettled,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.inkMuted,
              ),
            ),
            const SizedBox(height: BlTokens.space1),
            for (final bill in payment.settled) _SettledRow(bill: bill),
            if (payment.isReceipt && payment.onAccount.isPositive)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.wasooliOnAccount,
                        style: TextStyle(fontSize: 14, color: t.inkMuted),
                      ),
                    ),
                    BlMoney(payment.onAccount, size: 14),
                  ],
                ),
              ),
          ],
          if (lockText != null) ...[
            const SizedBox(height: BlTokens.space4),
            EntryNote(lockText),
          ],
          if (lock == PaymentLock.takenWithBill &&
              payment.counterBillId != null) ...[
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.entryOpenBill,
              icon: Icons.receipt_long_outlined,
              kind: BlButtonKind.secondary,
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReceiptScreen(
                      documentId: payment.counterBillId!,
                      docNo: payment.counterBillNo ?? '',
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: BlTokens.space4),
          if (allowance == null)
            BlButton(
              label: s.entryShare,
              icon: Icons.picture_as_pdf_outlined,
              kind: BlButtonKind.secondary,
              onPressed: () =>
                  unawaited(sharePaymentReceipt(context, ref, payment)),
            ),
          if (lock == PaymentLock.none) ...[
            const SizedBox(height: BlTokens.space3),
            if (mayCorrect) ...[
              if (allowance == null) ...[
                BlButton(
                  label: s.actionEdit,
                  icon: Icons.edit_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => unawaited(_edit(context)),
                ),
                const SizedBox(height: BlTokens.space3),
              ] else ...[
                EntryNote(s.entryAllowanceNoEdit),
                const SizedBox(height: BlTokens.space3),
              ],
              BlButton(
                label: s.entryCancel,
                icon: Icons.block,
                kind: BlButtonKind.danger,
                onPressed: () => unawaited(_cancel(context)),
              ),
            ] else
              EntryNote(s.entryNotAllowed),
          ],
        ],
      ),
    );
  }

  /// The same sheet the payment was taken with, filled in with it. Saving
  /// cancels this one and records the corrected one in one commit.
  Future<void> _edit(BuildContext context) async {
    final navigator = Navigator.of(context);
    final saved = payment.isReceipt
        ? await showReceivePaymentSheet(context, party: party, editing: payment)
        : await showPaySupplierSheet(context, party: party, editing: payment);
    // The page was about the payment that has just been cancelled; the
    // khata underneath now shows the one that replaced it.
    if (saved) navigator.pop();
  }

  Future<void> _cancel(BuildContext context) async {
    final navigator = Navigator.of(context);
    final cancelled = await showCancelEntrySheet(
      context,
      no: payment.paymentNo,
      cancel: (services, reason) => services.corrections.cancelPayment(
        services.actorNow(),
        paymentId: payment.id,
        reason: reason,
      ),
    );
    if (cancelled) navigator.pop();
  }
}

/// One step back or forward in an entry's history.
class _Link extends StatelessWidget {
  const _Link({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BlTokens.space1),
        child: Row(
          children: [
            Icon(Icons.history, size: 16, color: t.accent),
            const SizedBox(width: BlTokens.space2),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: t.accent),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _SettledRow extends StatelessWidget {
  const _SettledRow({required this.bill});

  final SettledBill bill;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final opensBill = bill.docType == 'sale_invoice';
    return InkWell(
      // A bill opens as it was printed, where it can be shared, returned or
      // cancelled — never edited.
      onTap: opensBill
          ? () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReceiptScreen(
                    documentId: bill.documentId,
                    docNo: bill.docNo,
                  ),
                ),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${bill.docNo} · ${bill.dateLocal}',
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
            ),
            BlMoney(bill.amount, size: 14),
          ],
        ),
      ),
    );
  }
}

/// Hands the customer a receipt for a payment, as a PDF through the share
/// sheet — the paper version of a khata line, for the day the shop and the
/// customer disagree about it.
Future<void> sharePaymentReceipt(
  BuildContext context,
  WidgetRef ref,
  PaymentDetail payment,
) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return;
    final bytes = await paymentReceiptPdf(
      payment,
      shop: firm.toReceiptShop(),
      // Read on the customer's phone, not this one: the face for an Urdu
      // name has to travel inside the file.
      unicodeFont: await PdfUnicodeFont.bytes(),
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${paymentReceiptFileName(payment.paymentNo)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: payment.paymentNo,
      ),
    );
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
    );
  }
}
