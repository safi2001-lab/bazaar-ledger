
import 'package:flutter/services.dart';

/// The face a shared PDF carries so it can say Urdu.
///
/// ## Why a PDF needs its own font when the thermal path does not
///
/// The thermal path draws Urdu on this phone, with this phone's fonts, and
/// sends the result as pixels. A PDF is read somewhere else — on a customer's
/// handset, in whatever viewer they have — so there is no system fallback to
/// lean on. Whatever glyphs the file does not carry, it does not have.
///
/// The base fonts the receipt uses are Courier and Helvetica, chosen because
/// they are Type 1 and need no embedding, and because Courier's figures are
/// tabular, which is the whole requirement for a column of money. Neither has
/// any Unicode support at all. So Urdu in the PDF did not become question
/// marks the way the thermal path degrades — it became nothing, silently, on
/// the copy that goes to the customer over WhatsApp.
///
/// ## What it costs
///
/// Noto Naskh Arabic Regular is a 178 KB file that deflates to 92 KB inside
/// the APK — measured, not estimated — against release builds at 27 MB under
/// a 30 MB ceiling. It is script-specific already, so there is no subset
/// worth cutting and no letter worth risking cutting: a subset chosen from
/// the strings this app knows about would drop the one a shopkeeper actually
/// types.
///
/// In each generated PDF it costs far less. The pdf package embeds only the
/// glyphs a document uses, so a receipt with an Urdu shop name and two Urdu
/// item names grows by about 2.6 KB.
///
/// Naskh rather than Nastaliq for the same reason the thermal path uses the
/// system face: Nastaliq is what Urdu is properly set in, and it is a 300 KB
/// to 2 MB face. That is a preference, and it belongs behind a setting.
///
/// ## Loaded once
///
/// Read from the asset bundle on first use and kept. A shopkeeper sharing
/// twenty bills in an evening should not re-read 178 KB twenty times, and the
/// share button is on the path with a customer still at the counter.
final class PdfUnicodeFont {
  const PdfUnicodeFont._();

  static const _asset = 'assets/fonts/NotoNaskhArabic-Regular.ttf';

  static Uint8List? _cached;

  /// The font bytes, or null if the asset could not be read.
  ///
  /// Null rather than a throw. A missing font is a receipt whose Urdu is
  /// missing, which is bad; a throw here is a share button that fails for a
  /// shop whose name is in Latin and never needed the font at all, which is
  /// worse. The caller passes whatever this returns straight through, and the
  /// PDF renders either way.
  static Future<Uint8List?> bytes() async {
    if (_cached != null) return _cached;
    try {
      final data = await rootBundle.load(_asset);
      return _cached = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } on Object {
      return null;
    }
  }
}
