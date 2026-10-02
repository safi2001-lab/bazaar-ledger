/// Sending a document again, whenever it is wanted (M30).
///
/// Shopkeepers testing the app said it plainly: "when we make an invoice
/// there is a share option, but if we want to share the invoice later we
/// can't". The share lived on the receipt screen that opens after a sale, and
/// the only road back to it was a newest-first list with no search. This is
/// the one place a bill, a quotation, a challan or a delivery leaves the
/// phone from, wherever it was found: as a PDF, as a picture, or as a message
/// straight into the customer's WhatsApp chat.
///
/// ## What this does not do
///
/// It does not talk to WhatsApp, or to Meta, or to anybody, any more than
/// the khata's reminder does. `whatsapp://send` is an Android intent that
/// resolves to the app already on the phone, never `wa.me`, which opens a
/// browser to Meta when WhatsApp is missing. A file goes through the system
/// share sheet, because a `whatsapp://send` link carries text and nothing
/// else; the message rides with the file as its caption, and the shopkeeper
/// picks WhatsApp and the customer there.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../printing/pdf_font.dart';
import '../printing/receipt_picture.dart';
import 'receipt_file_name.dart';

/// One document, ready to leave the phone: the paper, and who it is for.
final class OutgoingDocument {
  const OutgoingDocument({required this.receipt, this.recipient});

  final ReceiptData receipt;

  /// Null for a walk-in, who has nobody to send it to.
  final DocumentRecipient? recipient;

  /// The few lines that travel beside the file, or alone into the chat.
  String get message => billMessage(receipt);

  /// The number WhatsApp can reach them on, or null when there is none or
  /// the khata's number is not a Pakistani mobile.
  String? get whatsapp => whatsappNumber(recipient?.phone);

  /// [documentId] read for sending, or null when it is not this shop's.
  static Future<OutgoingDocument?> load(
    AppServices services,
    String documentId,
  ) async {
    final firm = await services.queries.currentFirm();
    if (firm == null) return null;
    final receipt = await services.queries.receiptFor(firm.id, documentId);
    if (receipt == null) return null;
    final status = await services.queries.documentStatus(firm.id, documentId);
    final printed = await services.printing.historyFor(firm.id, documentId);
    return OutgoingDocument(
      // Marked as what it is now, on what leaves: a bill cancelled since is
      // sent saying so, and one whose original already went to paper is
      // sent as the duplicate it is.
      receipt: receipt.copyWith(
        isCancelled: status == 'void',
        isReprint: printed.any((job) => job.status == PrintJobStatus.printed),
      ),
      recipient: await services.queries.recipientOf(firm.id, documentId),
    );
  }
}

/// How a "send on WhatsApp" left the phone.
enum WhatsAppOutcome {
  /// WhatsApp opened on the customer's own chat with the message typed.
  chat,

  /// The customer has a number but WhatsApp is not here, so the PDF went to
  /// the share sheet instead, which reaches SMS and everything else.
  shared,

  /// No number for this customer, or a walk-in: the PDF went to the share
  /// sheet, to be sent to whoever the shopkeeper picks.
  noNumber,
}

/// The PDF of [doc], with its message beside it.
Future<void> sharePdf(AppServices services, OutgoingDocument doc) async {
  final file = await _write(
    receiptFileName(doc.receipt.docNo),
    await services.receipts.toPdf(
      doc.receipt,
      // A PDF carries its own fonts: it is read on the customer's phone, not
      // this one, so there is no system fallback to fall back to.
      unicodeFont: await PdfUnicodeFont.bytes(),
    ),
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: doc.receipt.docNo,
      text: doc.message,
    ),
  );
}

/// A picture of [doc], with its message beside it.
Future<void> sharePicture(AppServices services, OutgoingDocument doc) async {
  final file = await _write(
    receiptFileName(doc.receipt.docNo, extension: 'png'),
    await const ReceiptPicture().png(services.receipts, doc.receipt),
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      subject: doc.receipt.docNo,
      text: doc.message,
    ),
  );
}

/// [doc] to its customer on WhatsApp.
///
/// With a number WhatsApp can reach, their own chat opens with the bill's
/// details typed, and the shopkeeper presses send. Without one — a walk-in,
/// a name in the khata and nothing else, a landline — or with WhatsApp not
/// installed, the PDF goes to the share sheet with the same message, so the
/// bill still leaves rather than the button saying no.
Future<WhatsAppOutcome> sendOnWhatsApp(
  AppServices services,
  OutgoingDocument doc,
) async {
  final number = doc.whatsapp;
  if (number == null) {
    await sharePdf(services, doc);
    return WhatsAppOutcome.noNumber;
  }

  final uri = Uri.parse(
    'whatsapp://send?phone=$number&text=${Uri.encodeComponent(doc.message)}',
  );
  // `canLaunchUrl` answers from the <queries> block in the manifest, which
  // names com.whatsapp and com.whatsapp.w4b for the khata's reminder.
  if (await canLaunchUrl(uri) &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return WhatsAppOutcome.chat;
  }
  await sharePdf(services, doc);
  return WhatsAppOutcome.shared;
}

/// [bytes] as [name] in the temporary directory, flushed before the share
/// sheet is asked for: a sheet handed a path still being written sends half
/// a file.
Future<File> _write(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
