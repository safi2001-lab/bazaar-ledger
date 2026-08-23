import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// How a reminder leaves the phone, and what it does when it cannot.
enum ReminderOutcome {
  /// WhatsApp opened on this customer's chat with the message ready.
  whatsapp,

  /// WhatsApp is not installed, or the number is not one it can reach, so the
  /// system share sheet was offered instead. That reaches SMS, which plenty
  /// of this market still uses.
  shared,

  /// Nothing to chase.
  nothingOwed,

  /// No number to chase it on.
  noNumber,
}

/// Sends [party] a reminder about what they owe.
///
/// ## What this does not do
///
/// It does not talk to WhatsApp, or to Meta, or to anybody. There is no
/// token, no account, no endpoint and no Business API. The `whatsapp://`
/// scheme is an Android intent that resolves to the app already on the phone,
/// and the message is handed to it the way any share is.
///
/// Deliberately never `wa.me/...`. That URL is the common recipe and it opens
/// a browser to Meta when WhatsApp is absent — a network call this app does
/// not make, on behalf of a shopkeeper who was told it never would. The
/// fallback is the system share sheet.
Future<ReminderOutcome> sendReminder({
  required String shopName,
  required PartySummary party,
  String? oldestBillDate,
}) async {
  if (!party.balance.isPositive) return ReminderOutcome.nothingOwed;

  final message = reminderMessage(
    shopName: shopName,
    customerName: party.name,
    balance: party.balance,
    oldestBillDate: oldestBillDate,
  );

  final number = whatsappNumber(party.phone);
  if (number == null) {
    // No number, or one WhatsApp cannot reach. The message still exists and
    // the shopkeeper may want to read it out, so the sheet is offered rather
    // than the whole thing being refused.
    await SharePlus.instance.share(ShareParams(text: message));
    return ReminderOutcome.noNumber;
  }

  final uri = Uri.parse(
    'whatsapp://send?phone=$number&text=${Uri.encodeComponent(message)}',
  );

  // `canLaunchUrl` answers from the <queries> block in the manifest. Without
  // that block it returns false on Android 11 and above however installed
  // WhatsApp is, which is why the block exists.
  if (await canLaunchUrl(uri) &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return ReminderOutcome.whatsapp;
  }

  await SharePlus.instance.share(ShareParams(text: message));
  return ReminderOutcome.shared;
}
