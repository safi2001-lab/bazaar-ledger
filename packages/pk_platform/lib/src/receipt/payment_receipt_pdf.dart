import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';

import 'printable.dart';

/// A payment, as a page the customer can be sent (M31).
///
/// "Paisay mil gaye" on WhatsApp is what a customer gets today, and it is
/// worth nothing the day they and the shop disagree. This is the paper
/// version of a khata entry: the receipt number, the date, who paid, how
/// much and how, which bills it went against and what was left on account,
/// and who at the shop took it. A payment the shop made to a supplier comes
/// out as a voucher the same way.
///
/// A5, like a bill, and set in the same faces for the same reasons — Courier
/// for the money so a column of figures lines up, Helvetica for the words,
/// and [unicodeFont] as the fallback that lets a name in Urdu survive into a
/// file read on somebody else's phone. English, as the bill is: it is the
/// document a dispute is settled with.
///
/// A cancelled payment still prints, marked CANCELLED with its reason, so a
/// customer holding the first copy can be shown why it no longer stands.
///
/// [compress] is for tests, which read the words back out of the page.
Future<Uint8List> paymentReceiptPdf(
  PaymentDetail payment, {
  required ReceiptShop shop,
  Uint8List? unicodeFont,
  bool compress = true,
}) async {
  final fallback = unicodeFont == null
      ? null
      : pw.Font.ttf(ByteData.view(unicodeFont.buffer));
  final title = payment.isReceipt ? 'Payment Receipt' : 'Payment Voucher';
  final doc = pw.Document(
    title: '$title ${payment.paymentNo}',
    author: shop.name,
    compress: compress,
    theme: fallback == null
        ? null
        : pw.ThemeData.withFont(fontFallback: [fallback]),
  );

  final mono = pw.Font.courier();
  final monoBold = pw.Font.courierBold();
  final sans = pw.Font.helvetica();
  final sansBold = pw.Font.helveticaBold();
  final body = pw.TextStyle(font: sans, fontSize: 10);
  final muted = pw.TextStyle(font: sans, fontSize: 9, color: PdfColors.grey700);

  pw.Widget words(String value, {pw.TextStyle? style}) => pw.Text(
    value,
    style: style ?? body,
    textDirection: isPrintableLatin(value) ? null : pw.TextDirection.rtl,
  );

  pw.Widget row(String label, String value, {bool money = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 92, child: pw.Text(label, style: muted)),
        pw.Expanded(
          child: money
              ? pw.Text(value, style: pw.TextStyle(font: mono, fontSize: 10))
              : words(value),
        ),
      ],
    ),
  );

  final shopLines = [
    ?shop.addressLine1,
    ?shop.city,
    if (shop.phone case final phone?) 'Ph: $phone',
  ];
  final how = [
    _modeLabel(payment.mode),
    if (payment.chequeNo case final no?) 'No. $no',
    ?payment.chequeBank,
    if (payment.chequeDue case final due?) 'dated ${_date(due.value)}',
  ].join(', ');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: words(
              shop.name,
              style: pw.TextStyle(font: sansBold, fontSize: 14),
            ),
          ),
          for (final line in shopLines)
            pw.Center(child: words(line, style: muted)),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(font: sansBold, fontSize: 12),
            ),
          ),
          if (payment.isCancelled) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'CANCELLED',
                style: pw.TextStyle(
                  font: sansBold,
                  fontSize: 14,
                  color: PdfColors.red800,
                ),
              ),
            ),
            if (payment.cancelReason case final why?)
              pw.Center(child: words(why, style: muted)),
          ],
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 0.6),
          row(
            payment.isReceipt ? 'Receipt No' : 'Voucher No',
            payment.paymentNo,
          ),
          row('Date', _date(payment.dateLocal)),
          if (payment.partyName case final name?)
            row(payment.isReceipt ? 'Received from' : 'Paid to', name),
          row('By', how),
          if (payment.reference case final reference?)
            row('Reference', reference),
          if (payment.notes case final notes?) row('Note', notes),
          pw.Divider(thickness: 0.6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                payment.isReceipt ? 'Amount received' : 'Amount paid',
                style: pw.TextStyle(font: sansBold, fontSize: 11),
              ),
              pw.Text(
                'Rs ${payment.amount.amountOnly}',
                style: pw.TextStyle(font: monoBold, fontSize: 13),
              ),
            ],
          ),
          if (payment.settled.isNotEmpty || payment.onAccount.isPositive) ...[
            pw.SizedBox(height: 8),
            pw.Text('Against', style: muted),
            for (final bill in payment.settled)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${bill.docNo}  (${_date(bill.dateLocal)})',
                    style: body,
                  ),
                  pw.Text(
                    bill.amount.amountOnly,
                    style: pw.TextStyle(font: mono, fontSize: 10),
                  ),
                ],
              ),
            if (payment.isReceipt && payment.onAccount.isPositive)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('On account (advance)', style: body),
                  pw.Text(
                    payment.onAccount.amountOnly,
                    style: pw.TextStyle(font: mono, fontSize: 10),
                  ),
                ],
              ),
          ],
          pw.Spacer(),
          pw.Divider(thickness: 0.6),
          row(payment.isReceipt ? 'Received by' : 'Paid by', payment.enteredBy),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('Shukriya!', style: muted)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// A file name for a payment's receipt, safe on any filesystem it lands on.
String paymentReceiptFileName(String paymentNo) {
  final safe = paymentNo
      .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')
      .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  return '${safe.isEmpty ? 'payment' : safe}.pdf';
}

/// `2026-08-23` as `23-08-2026`, the way a bill prints its date.
String _date(String iso) {
  final parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}-${parts[1]}-${parts[0]}' : iso;
}

String _modeLabel(String mode) => switch (mode) {
  'cash' => 'Cash',
  'bank_transfer' => 'Bank Transfer',
  'jazzcash' => 'JazzCash',
  'easypaisa' => 'EasyPaisa',
  'raast' => 'Raast',
  'card' => 'Card',
  'cheque' => 'Cheque',
  _ => 'Adjustment',
};
