import 'dart:io';
import 'package:share_plus/share_plus.dart';

class ShareIntentService {
  /// Share an invoice PDF or Image via native OS Share intent (WhatsApp, Email, etc.)
  static Future<void> shareInvoiceFile(File file, String invoiceNumber) async {
    final xFile = XFile(file.path);
    await Share.shareXFiles(
      [xFile],
      text: 'Here is your Invoice #$invoiceNumber from our store.',
      subject: 'Invoice #$invoiceNumber',
    );
  }

  /// Share text reminder for Khata Udhaar balance
  static Future<void> shareKhataReminder(String partyName, double balanceAmount) async {
    final message = '''
Hello $partyName,

This is a gentle reminder that your outstanding Khata (Credit) balance is Rs. ${balanceAmount.toStringAsFixed(2)}.
Please arrange the payment at your earliest convenience.

Thank you!
''';
    await Share.share(message, subject: 'Payment Reminder');
  }
}
