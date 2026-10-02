/// A filename for a shared bill, safe on any filesystem it might land on.
///
/// A document number is shop-controlled. The default series is `INV-2627-0001`
/// and looks harmless, but the numbering format is a setting and a shop that
/// has always written `INV/26-27/0001` on its pad will type exactly that. A
/// slash goes straight into a path: on Android the write lands in a directory
/// that does not exist and throws, on the share path, with a customer waiting
/// — and only for the shops that use one.
///
/// The other half is Urdu. A shopkeeper may name their series in Urdu script,
/// and while most filesystems accept it, the file then travels through
/// WhatsApp to whatever the customer's phone does with it. Latin, digits,
/// dash and underscore is the set that survives that trip intact.
library;

/// `docNo` reduced to characters a file may be named with.
///
/// Never empty: a bill whose number reduces to nothing still has to be shared,
/// and a file called `.pdf` is one a share sheet will not offer.
///
/// [extension] is `png` for the picture of a bill (M30), which goes through
/// the same filesystem and the same WhatsApp as the PDF.
String receiptFileName(String docNo, {String extension = 'pdf'}) {
  final safe = docNo.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');

  // Dashes come off the ends as well as underscores. An Urdu prefix like
  // `بل-0001` reduces to `__-0001`, and a leading dash is legal but reads as
  // a command-line flag to half the tools a shared file passes through.
  final trimmed = safe.replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  return '${trimmed.isEmpty ? 'bill' : trimmed}.$extension';
}
