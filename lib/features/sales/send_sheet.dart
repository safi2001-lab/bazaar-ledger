import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';
import 'print_bill.dart';
import 'send_bill.dart';

/// One document, read for sending: its paper and who it goes to.
final outgoingDocumentProvider = FutureProvider.autoDispose
    .family<OutgoingDocument?, String>((ref, documentId) async {
      ref.watch(refreshTickProvider);
      return OutgoingDocument.load(ref.watch(appServicesProvider), documentId);
    });

/// The ways a document leaves the phone, from wherever it was found (M30).
///
/// Opened from a bill's row in the sales list or on the home screen, so a
/// bill from last month goes to its customer in two taps without being
/// opened first. [offerPrint] is for sale bills, and only shows when this
/// counter has a printer.
Future<void> showSendSheet(
  BuildContext context, {
  required String documentId,
  required String docNo,
  bool offerPrint = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _SendSheet(
    documentId: documentId,
    docNo: docNo,
    offerPrint: offerPrint,
    // The row's own context, which outlives the sheet: a print's answer, or
    // its "did it print?" question, comes after the sheet has closed.
    host: context,
  ),
);

enum _Way { whatsapp, pdf, picture }

class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({
    required this.documentId,
    required this.docNo,
    required this.offerPrint,
    required this.host,
  });

  final String documentId;
  final String docNo;
  final bool offerPrint;
  final BuildContext host;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  _Way? _working;
  String? _failure;

  Future<void> _send(_Way way, OutgoingDocument doc) async {
    // First statement. Rendering a PDF takes long enough on an entry handset
    // that a shopkeeper who sees nothing happen taps again, and each tap is
    // its own share sheet.
    if (_working != null) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(widget.host);
    final navigator = Navigator.of(context);
    setState(() {
      _working = way;
      _failure = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      switch (way) {
        case _Way.pdf:
          await sharePdf(services, doc);
        case _Way.picture:
          await sharePicture(services, doc);
        case _Way.whatsapp:
          final outcome = await sendOnWhatsApp(services, doc);
          // Said, so a shopkeeper who expected the customer's chat knows why
          // a share sheet came up instead.
          if (outcome != WhatsAppOutcome.chat) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  outcome == WhatsAppOutcome.noNumber
                      ? s.sendNoNumber
                      : s.sendNoWhatsApp,
                ),
              ),
            );
          }
      }
      if (mounted) navigator.pop();
    } on Object catch (error) {
      // In the sheet, not under it: a SnackBar behind a bottom sheet is a
      // failure nobody reads.
      if (mounted) {
        setState(() => _failure = '${s.commonSomethingWentWrong}: $error');
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  void _print() {
    if (_working != null) return;
    Navigator.of(context).pop();
    final host = widget.host;
    if (!host.mounted) return;
    unawaited(printBill(host, documentId: widget.documentId));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final outgoing = ref.watch(outgoingDocumentProvider(widget.documentId));
    final hasPrinter = ref.watch(printerSettingsProvider).valueOrNull != null;

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: outgoing.when(
        loading: () => const BlSkeletonList(rows: 3),
        error: (error, _) =>
            BlError(title: s.commonSomethingWentWrong, message: '$error'),
        data: (doc) {
          if (doc == null) return BlEmpty(title: s.commonNothingSaved);
          final recipient = doc.recipient;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.sendTitle(widget.docNo),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                Text(
                  recipient == null
                      ? s.sendWalkIn
                      : [recipient.name, ?recipient.phone].join(' · '),
                  style: TextStyle(fontSize: 14, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space3),
                _WayTile(
                  icon: Icons.chat_outlined,
                  title: s.sendWhatsApp,
                  subtitle: doc.whatsapp == null
                      ? s.sendWhatsAppNoNumber
                      : s.sendWhatsAppTo(recipient!.name),
                  busy: _working == _Way.whatsapp,
                  onTap: () => unawaited(_send(_Way.whatsapp, doc)),
                ),
                _WayTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: s.receiptSharePdf,
                  subtitle: s.sendPdfHint,
                  busy: _working == _Way.pdf,
                  onTap: () => unawaited(_send(_Way.pdf, doc)),
                ),
                _WayTile(
                  icon: Icons.image_outlined,
                  title: s.sendPicture,
                  subtitle: s.sendPictureHint,
                  busy: _working == _Way.picture,
                  onTap: () => unawaited(_send(_Way.picture, doc)),
                ),
                if (widget.offerPrint && hasPrinter)
                  _WayTile(
                    icon: Icons.print_outlined,
                    title: s.receiptPrint,
                    subtitle: s.sendPrintHint,
                    busy: false,
                    onTap: _print,
                  ),
                if (_failure != null) ...[
                  const SizedBox(height: BlTokens.space3),
                  Text(
                    _failure!,
                    style: TextStyle(color: t.danger, fontSize: 14),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One way to send, as a row a thumb can hit.
class _WayTile extends StatelessWidget {
  const _WayTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: BlCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: busy
                  ? CircularProgressIndicator(strokeWidth: 2, color: t.ink)
                  : Icon(icon, color: t.ink),
            ),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PDF, WhatsApp and a picture, as buttons, for a screen that already shows
/// the document: the receipt after a sale, or a delivery or quotation opened
/// from its list.
///
/// Loads the document as it is tapped rather than holding it, so what goes
/// out is what the books say now.
class SendButtons extends ConsumerStatefulWidget {
  const SendButtons({super.key, required this.documentId, this.onFailure});

  final String documentId;

  /// Where a failure is said. A SnackBar when null; a sheet passes its own,
  /// because a SnackBar behind a bottom sheet is never read.
  final void Function(String message)? onFailure;

  @override
  ConsumerState<SendButtons> createState() => _SendButtonsState();
}

class _SendButtonsState extends ConsumerState<SendButtons> {
  _Way? _working;

  Future<void> _send(_Way way) async {
    // First statement. Setting it inside the `setState` below let two taps
    // in one frame both through, and each one renders a PDF and opens its
    // own share sheet.
    if (_working != null) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _working = way;
    setState(() {});
    try {
      final services = ref.read(appServicesProvider);
      final doc = await OutgoingDocument.load(services, widget.documentId);
      if (doc == null) throw StateError(s.commonNothingSaved);
      if (!mounted) return;
      switch (way) {
        case _Way.pdf:
          await sharePdf(services, doc);
        case _Way.picture:
          await sharePicture(services, doc);
        case _Way.whatsapp:
          final outcome = await sendOnWhatsApp(services, doc);
          if (outcome != WhatsAppOutcome.chat) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  outcome == WhatsAppOutcome.noNumber
                      ? s.sendNoNumber
                      : s.sendNoWhatsApp,
                ),
              ),
            );
          }
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = '${s.commonSomethingWentWrong}: $error';
      if (widget.onFailure case final say?) {
        say(message);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      _working = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final busy = _working != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlButton(
          label: s.receiptSharePdf,
          icon: Icons.picture_as_pdf_outlined,
          kind: BlButtonKind.secondary,
          busy: _working == _Way.pdf,
          onPressed: busy ? null : () => unawaited(_send(_Way.pdf)),
        ),
        const SizedBox(height: BlTokens.space2),
        Row(
          children: [
            Expanded(
              child: BlButton(
                label: s.sendWhatsAppShort,
                icon: Icons.chat_outlined,
                kind: BlButtonKind.secondary,
                expand: true,
                busy: _working == _Way.whatsapp,
                onPressed: busy ? null : () => unawaited(_send(_Way.whatsapp)),
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            Expanded(
              child: BlButton(
                label: s.sendPictureShort,
                icon: Icons.image_outlined,
                kind: BlButtonKind.secondary,
                expand: true,
                busy: _working == _Way.picture,
                onPressed: busy ? null : () => unawaited(_send(_Way.picture)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
