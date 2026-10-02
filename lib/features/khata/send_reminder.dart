import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// How a reminder leaves the phone, and what it does when it cannot.
enum ReminderOutcome {
  /// WhatsApp opened on this customer's chat with the message ready.
  whatsapp,

  /// The phone's own messages app opened to this customer with the message
  /// ready (M39). The shopkeeper presses Send there.
  sms,

  /// WhatsApp (or the messages app) is not here, or the number is not one
  /// it can reach, so the system share sheet was offered instead. That
  /// reaches SMS, which plenty of this market still uses.
  shared,

  /// Nothing to chase.
  nothingOwed,

  /// No number to chase it on.
  noNumber,
}

/// Hands [message] to [party]'s WhatsApp chat, or to the phone's messages
/// app when [channel] is SMS (M39).
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
///
/// Nor does it send an SMS. `sms:` opens the phone's own messages app with
/// the number and the words filled in, and the shopkeeper taps Send there,
/// from their own SIM. The app never asks for SEND_SMS: Play restricts it
/// to default SMS apps, and a khata that could text customers by itself is
/// one a shopkeeper cannot see doing it.
///
/// The message is written by the caller, from the shop's template in the
/// customer's language (`UdhaarServices.reminderFor`).
Future<ReminderOutcome> sendReminder({
  required String message,
  required PartySummary party,
  ReminderChannel channel = ReminderChannel.whatsapp,
}) async {
  if (!party.balance.isPositive) return ReminderOutcome.nothingOwed;

  final number = whatsappNumber(party.phone);
  if (number == null) {
    // No number, or one WhatsApp cannot reach. The message still exists and
    // the shopkeeper may want to read it out, so the sheet is offered rather
    // than the whole thing being refused.
    await SharePlus.instance.share(ShareParams(text: message));
    return ReminderOutcome.noNumber;
  }

  final uri = channel == ReminderChannel.sms
      ? Uri.parse('sms:+$number?body=${Uri.encodeComponent(message)}')
      : Uri.parse(
          'whatsapp://send?phone=$number&text=${Uri.encodeComponent(message)}',
        );

  // `canLaunchUrl` answers from the <queries> block in the manifest. Without
  // that block it returns false on Android 11 and above however installed
  // WhatsApp is, which is why the block exists; it names the `sms` scheme
  // too since M39.
  if (await canLaunchUrl(uri) &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return channel == ReminderChannel.sms
        ? ReminderOutcome.sms
        : ReminderOutcome.whatsapp;
  }

  await SharePlus.instance.share(ShareParams(text: message));
  return ReminderOutcome.shared;
}

/// The channel to write in the log for [outcome], or null when nothing left
/// the phone.
ReminderChannel? channelOf(ReminderOutcome outcome) => switch (outcome) {
  ReminderOutcome.whatsapp => ReminderChannel.whatsapp,
  ReminderOutcome.sms => ReminderChannel.sms,
  ReminderOutcome.shared || ReminderOutcome.noNumber => ReminderChannel.share,
  ReminderOutcome.nothingOwed => null,
};
