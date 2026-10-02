import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// How a list left the phone.
enum OrderSendOutcome {
  /// WhatsApp opened on the supplier's own chat with the list typed.
  chat,

  /// Through the share sheet: no number WhatsApp can reach, or no WhatsApp.
  shared,
}

/// [text] — a purchase order or the shortage list, in words — to the chat
/// of [number] on WhatsApp, or to the share sheet when there is no number
/// or no WhatsApp (M41).
///
/// The same road a bill sent again takes (M30) and the khata's reminder
/// before it: `whatsapp://send`, an intent the phone's own WhatsApp
/// answers, never `wa.me`, which opens a browser to Meta when WhatsApp is
/// missing. Nothing here talks to anybody; the shopkeeper presses send.
Future<OrderSendOutcome> sendOrderText(String text, {String? number}) async {
  if (number != null) {
    final uri = Uri.parse(
      'whatsapp://send?phone=$number&text=${Uri.encodeComponent(text)}',
    );
    if (await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return OrderSendOutcome.chat;
    }
  }
  await SharePlus.instance.share(ShareParams(text: text));
  return OrderSendOutcome.shared;
}
