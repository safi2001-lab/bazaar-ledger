/// The forms one physical barcode can arrive in.
///
/// The same printed symbol on the same packet reaches this app as different
/// strings depending on what read it, and a shop will have both in the same
/// afternoon:
///
///   * A UPC-A barcode is twelve digits. Almost every hardware wedge sends
///     those twelve.
///   * ML Kit — and most camera libraries — report UPC-A as EAN-13 with a
///     leading zero, because that is what UPC-A formally is. Thirteen digits.
///   * A shopkeeper typing from the packet copies whatever is printed under
///     the bars, which is the twelve.
///
/// So an exact-match lookup finds the item when the counter scans it with the
/// USB gun and fails when the same packet is scanned with the phone. Nothing
/// about that failure suggests a normalisation problem: it looks like the item
/// is missing, and the cashier adds it again by hand — which is how a
/// catalogue ends up with the same packet twice at two prices.
///
/// EAN-8 and EAN-13 are left alone. Only the UPC-A/EAN-13 leading zero is
/// ambiguous; stripping leading zeros generally would make `0123` and `123`
/// the same item, and they are not.
library;

/// Every string that could reasonably mean the same packet as [scanned].
///
/// Ordered most-likely-first, and always beginning with the input exactly as
/// it arrived — a lookup should prefer what was actually read over anything
/// this function inferred.
List<String> barcodeVariants(String scanned) {
  final code = scanned.trim();
  if (code.isEmpty) return const [];

  final variants = <String>[code];

  // Only digits can be a UPC or an EAN. A shop's own code like `CHAWAL-5KG`
  // has no leading-zero form and must not gain one.
  if (!RegExp(r'^\d+$').hasMatch(code)) return variants;

  // Twelve digits: the EAN-13 a camera would report for the same packet.
  if (code.length == 12) variants.add('0$code');

  // Thirteen digits beginning with zero: the UPC-A a wedge would send.
  if (code.length == 13 && code.startsWith('0')) {
    variants.add(code.substring(1));
  }

  return variants;
}
