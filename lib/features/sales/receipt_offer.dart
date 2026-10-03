/// The customer's receipt, offered the moment money moves (M70).
///
/// After a bill is saved, a payment is taken on the khata, goods come back
/// and a supplier is paid, the party is offered a receipt: a WhatsApp
/// message in their own language (M39) saying what moved and where the
/// khata stands now — Vyapar's transaction message, with the balance in it
/// — and for a bill, its PDF or its picture as well.
///
/// ## Asked, opened by itself, or never
///
/// Each party is asked every time ("Har dafa poochhein"), has WhatsApp
/// opened on their chat with the message typed ("Khud bhejein"), or is
/// never offered one ("Kabhi nahi"); one nobody set is offered as the shop
/// says in Settings. Nobody is offered one who has no number WhatsApp can
/// reach, and a walk-in never is.
///
/// ## Nothing is sent from here
///
/// "Khud bhejein" opens the chat; it does not press Send. The app holds no
/// SEND_SMS and talks to no API: `whatsapp://send` is the same intent the
/// khata's reminder uses (M3, M39), resolved by the WhatsApp already on
/// the phone, never `wa.me`. When the chat has opened, or the file has gone
/// to the share sheet, the paper's history says so with M54's share codes —
/// the bill's or the return's on the document, a payment's on the payment.
///
/// ## Out of the way
///
/// Started after the money is in the books and never awaited by the screen
/// that moved it: a receipt that cannot be offered — the read failed, the
/// sheet was dismissed — never stands between the shop and the next
/// customer, and the money stays moved.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/reminder_queue_screen.dart' show reminderLanguageName;
import 'send_bill.dart';

/// After [sale] is saved at the counter.
void offerAfterSale(NavigatorState navigator, PostedSale sale) => unawaited(
  offerReceipt(
    navigator,
    MoneyMoved(
      kind: MoneyMove.sale,
      documentId: sale.documentId,
      number: sale.docNo,
      amount: sale.total,
      paid: sale.paid,
    ),
  ),
);

/// After [receipt] is taken against a customer's khata.
void offerAfterReceipt(
  NavigatorState navigator,
  RecordedReceipt receipt, {
  bool byCheque = false,
}) => unawaited(
  offerReceipt(
    navigator,
    MoneyMoved(
      kind: MoneyMove.received,
      paymentId: receipt.paymentId,
      number: receipt.paymentNo,
      amount: receipt.amount,
      byCheque: byCheque,
    ),
  ),
);

/// After goods come back on [recorded].
void offerAfterReturn(NavigatorState navigator, RecordedReturn recorded) =>
    unawaited(
      offerReceipt(
        navigator,
        MoneyMoved(
          kind: MoneyMove.saleReturn,
          documentId: recorded.documentId,
          number: recorded.docNo,
          amount: recorded.total,
          paid: recorded.refunded,
        ),
      ),
    );

/// After [paid] goes to a supplier.
void offerAfterSupplierPayment(
  NavigatorState navigator,
  RecordedReceipt paid, {
  bool byCheque = false,
}) => unawaited(
  offerReceipt(
    navigator,
    MoneyMoved(
      kind: MoneyMove.paidSupplier,
      paymentId: paid.paymentId,
      number: paid.paymentNo,
      amount: paid.amount,
      byCheque: byCheque,
    ),
  ),
);

/// Offers [event]'s receipt over whatever [navigator] shows by then: the
/// bill, or the khata the sheet closed onto.
Future<void> offerReceipt(NavigatorState navigator, MoneyMoved event) async {
  if (!navigator.mounted) return;
  final services = ProviderScope.containerOf(
    navigator.context,
    listen: false,
  ).read(appServicesProvider);
  final MoneyReceiptReady? ready;
  try {
    ready = await services.moneyReceipt(event);
  } on Object {
    return;
  }
  if (ready == null || !navigator.mounted) return;
  if (ready.offer == ReceiptOffer.auto &&
      await openReceiptChat(services, ready)) {
    return;
  }
  // Asked — or "Khud bhejein" with no WhatsApp to open, when the sheet is
  // the way the receipt still goes.
  if (!navigator.mounted) return;
  final offered = ready;
  await showModalBottomSheet<void>(
    context: navigator.context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReceiptOfferSheet(ready: offered),
  );
}

/// The party's own WhatsApp chat, opened with [ready]'s message typed;
/// written on the paper's history once it has opened. False when WhatsApp
/// would not open, and then nothing is written.
Future<bool> openReceiptChat(
  AppServices services,
  MoneyReceiptReady ready,
) async {
  final uri = Uri.parse(
    'whatsapp://send?phone=${ready.whatsapp}'
    '&text=${Uri.encodeComponent(ready.message)}',
  );
  try {
    if (!await canLaunchUrl(uri)) return false;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return false;
    }
  } on Object {
    return false;
  }
  try {
    await services.recordReceiptSent(ready, SharedVia.whatsapp);
  } on Object {
    // Said nowhere: the chat is open, which is what was asked.
  }
  return true;
}

/// A party's choice by its own name.
String receiptOfferName(AppStrings s, ReceiptOffer offer) => switch (offer) {
  ReceiptOffer.ask => s.receiptOfferAsk,
  ReceiptOffer.auto => s.receiptOfferAuto,
  ReceiptOffer.never => s.receiptOfferNever,
};

enum _Way { whatsapp, pdf, picture }

/// "Rashid Traders ko raseed bhejein?" — the words that will go, the ways
/// they can go, and what this party is offered from now on.
class ReceiptOfferSheet extends ConsumerStatefulWidget {
  const ReceiptOfferSheet({super.key, required this.ready});

  final MoneyReceiptReady ready;

  @override
  ConsumerState<ReceiptOfferSheet> createState() => _ReceiptOfferSheetState();
}

class _ReceiptOfferSheetState extends ConsumerState<ReceiptOfferSheet> {
  _Way? _working;
  String? _failure;
  bool _choosing = false;
  late ReceiptOffer _choice = widget.ready.ownChoice ?? widget.ready.offer;
  bool _kept = false;

  MoneyReceiptReady get _ready => widget.ready;

  Future<void> _whatsapp() async {
    // First statement: two taps in one frame both reach here.
    if (_working != null) return;
    final s = AppStrings.of(context);
    setState(() {
      _working = _Way.whatsapp;
      _failure = null;
    });
    final opened = await openReceiptChat(ref.read(appServicesProvider), _ready);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _working = null;
      _failure = s.receiptOfferNoWhatsApp;
    });
  }

  /// The bill itself, through the very doors its send sheet uses (M30),
  /// which write the share on its history (M54).
  Future<void> _file(_Way way) async {
    if (_working != null) return;
    final s = AppStrings.of(context);
    final documentId = _ready.event.documentId;
    if (documentId == null) return;
    setState(() {
      _working = way;
      _failure = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      final doc = await OutgoingDocument.load(
        services,
        documentId,
        thermal: way == _Way.picture ? ReceiptPaper.mm80 : null,
      );
      if (doc == null) throw StateError(s.commonNothingSaved);
      if (way == _Way.picture) {
        await sharePicture(services, doc);
      } else {
        await sharePdf(services, doc);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _failure = '${s.commonSomethingWentWrong}: $error');
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _choose(ReceiptOffer choice) async {
    if (_choosing || choice == _choice) return;
    final s = AppStrings.of(context);
    _choosing = true;
    try {
      await ref
          .read(appServicesProvider)
          .setReceiptOfferOf(_ready.partyId, choice);
      if (!mounted) return;
      setState(() {
        _choice = choice;
        _kept = true;
      });
      // Never again, then not now either.
      if (choice == ReceiptOffer.never) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _failure = '${s.commonSomethingWentWrong}: $error');
      }
    } finally {
      _choosing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final busy = _working != null;
    final isBill = _ready.event.kind == MoneyMove.sale;
    final mayChoose = ref
        .watch(appServicesProvider)
        .can(Permission.takePayments);

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.receiptOfferTitle(_ready.name),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              [
                ?_ready.phone,
                reminderLanguageName(s, _ready.language),
              ].join(' · '),
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            // The words exactly as they will be typed into the chat, in the
            // party's own script and direction.
            Container(
              padding: const EdgeInsets.all(BlTokens.space3),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(BlTokens.radiusSm),
                border: Border.all(color: t.line),
              ),
              child: SelectableText(
                _ready.message,
                textDirection: _ready.language == ReminderLanguage.urdu
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                style: TextStyle(fontSize: 14, height: 1.4, color: t.ink),
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.receiptOfferWhatsApp,
              icon: Icons.chat_outlined,
              big: true,
              expand: true,
              busy: _working == _Way.whatsapp,
              onPressed: busy ? null : () => unawaited(_whatsapp()),
            ),
            if (isBill) ...[
              const SizedBox(height: BlTokens.space2),
              Row(
                children: [
                  Expanded(
                    child: BlButton(
                      label: s.receiptOfferPdf,
                      icon: Icons.picture_as_pdf_outlined,
                      kind: BlButtonKind.secondary,
                      expand: true,
                      busy: _working == _Way.pdf,
                      onPressed: busy ? null : () => unawaited(_file(_Way.pdf)),
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: BlButton(
                      label: s.receiptOfferPicture,
                      icon: Icons.image_outlined,
                      kind: BlButtonKind.secondary,
                      expand: true,
                      busy: _working == _Way.picture,
                      onPressed: busy
                          ? null
                          : () => unawaited(_file(_Way.picture)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: BlTokens.space2),
            Text(
              s.receiptOfferNote,
              style: TextStyle(fontSize: 12, color: t.inkMuted),
            ),
            if (mayChoose) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.receiptOfferFromNow,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space1),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                children: [
                  for (final offer in ReceiptOffer.values)
                    ChoiceChip(
                      label: Text(receiptOfferName(s, offer)),
                      selected: _choice == offer,
                      onSelected: (_) => unawaited(_choose(offer)),
                    ),
                ],
              ),
              if (_kept)
                Text(
                  s.receiptOfferKept(_ready.name, receiptOfferName(s, _choice)),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_failure!, style: TextStyle(fontSize: 14, color: t.danger)),
            ],
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.receiptOfferLater,
              kind: BlButtonKind.ghost,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A party's own choice, on their form (M70): asked, opened by itself, or
/// never. Kept the moment it is tapped, as the offer sheet keeps it — it is
/// a setting of its own, not a field of the party.
class ReceiptOfferField extends ConsumerStatefulWidget {
  const ReceiptOfferField({super.key, required this.partyId});

  final String partyId;

  @override
  ConsumerState<ReceiptOfferField> createState() => _ReceiptOfferFieldState();
}

class _ReceiptOfferFieldState extends ConsumerState<ReceiptOfferField> {
  ReceiptOffer? _own;
  ReceiptOffer _shop = ReceiptOffer.ask;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final services = ref.read(appServicesProvider);
    try {
      final own = await services.receiptOfferOf(widget.partyId);
      final shop = await services.receiptOfferDefault();
      if (!mounted) return;
      setState(() {
        _own = own;
        _shop = shop;
        _loaded = true;
      });
    } on Object {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _choose(ReceiptOffer offer) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final s = AppStrings.of(context);
    _busy = true;
    try {
      await ref
          .read(appServicesProvider)
          .setReceiptOfferOf(widget.partyId, offer);
      if (!mounted) return;
      setState(() => _own = offer);
      messenger.showSnackBar(SnackBar(content: Text(s.receiptOfferSaved)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    if (!_loaded) return const SizedBox.shrink();
    final shown = _own ?? _shop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: BlTokens.space3),
        Text(
          s.partyReceiptOffer,
          style: TextStyle(fontSize: 13, color: t.inkMuted),
        ),
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final offer in ReceiptOffer.values)
              ChoiceChip(
                label: Text(receiptOfferName(s, offer)),
                selected: shown == offer,
                onSelected: (_) => unawaited(_choose(offer)),
              ),
          ],
        ),
        if (_own == null)
          Text(
            s.partyReceiptOfferShop,
            style: TextStyle(fontSize: 12, color: t.inkFaint),
          ),
      ],
    );
  }
}
