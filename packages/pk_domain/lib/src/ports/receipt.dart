import 'dart:typed_data';

import 'package:pk_money/pk_money.dart';

/// The shop, as it appears at the top of a receipt.
final class ReceiptShop {
  const ReceiptShop({
    required this.name,
    this.addressLine1,
    this.city,
    this.phone,
    this.ntn,
    this.strn,
    this.raastAlias,
    this.bankName,
    this.bankAccountTitle,
    this.bankIban,
    this.logo,
  });

  final String name;
  final String? addressLine1;
  final String? city;
  final String? phone;

  /// Printed only when the shop actually holds one. Most kiryana stores do
  /// not: under s.3(9) STA a non-Tier-1 retailer pays sales tax through the
  /// electricity bill, so a receipt that demands an NTN would be wrong for the
  /// majority of the market.
  final String? ntn;
  final String? strn;

  /// The shop's own Raast alias, printed as PLAIN TEXT — exactly like printing
  /// a phone number.
  ///
  /// We never synthesise a scheme QR payload. QR Standard s.8.1(a) reserves
  /// the scheme identifier to PSO/PSPs authorised by the State Bank, and
  /// breaching an SBP instruction is an offence under s.56 PS&EFT Act carrying
  /// up to three years or PKR 3 million. A bank-issued QR the merchant
  /// imported is rendered as an image; one is never constructed.
  final String? raastAlias;
  final String? bankName;
  final String? bankAccountTitle;
  final String? bankIban;

  /// A 1-bit bitmap, already rasterised. Optional.
  final MonoBitmap? logo;
}

/// One printed line of a receipt.
final class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qtyDisplay,
    required this.unitCode,
    required this.rate,
    required this.amount,
    this.discount = Money.zero,
    this.isFreeItem = false,
  });

  final String name;
  final String qtyDisplay;
  final String unitCode;
  final Rate rate;
  final Money amount;
  final Money discount;
  final bool isFreeItem;
}

/// One tender, as printed.
final class ReceiptTender {
  const ReceiptTender({
    required this.label,
    required this.amount,
    this.reference,
    this.isCash = false,
  });

  /// What the receipt prints, already translated.
  final String label;

  final Money amount;
  final String? reference;

  /// Whether real notes changed hands.
  ///
  /// Carried separately from [label] because the label is display text that
  /// changes with the language, and the one thing that must not depend on the
  /// shopkeeper's language setting is whether the cash drawer opens. A drawer
  /// that clicks on a card payment is a drawer somebody unplugs.
  final bool isCash;
}

/// Everything a receipt needs, with no reference to how it will be drawn.
final class ReceiptData {
  const ReceiptData({
    required this.shop,
    required this.docNo,
    required this.dateTimeLabel,
    required this.lines,
    required this.subtotal,
    required this.total,
    required this.tenders,
    required this.paid,
    required this.balance,
    required this.change,
    required this.cashierName,
    this.customerName,
    this.customerPhone,
    this.discount = Money.zero,
    this.tax = Money.zero,
    this.furtherTax = Money.zero,
    this.withholding = Money.zero,
    this.extraCharges = Money.zero,
    this.roundOff = Money.zero,
    this.previousBalance,
    this.footerLines = const [],
    this.bankQr,
    this.isReprint = false,
  });

  final ReceiptShop shop;
  final String docNo;
  final String dateTimeLabel;
  final String? customerName;
  final String? customerPhone;
  final String cashierName;

  final List<ReceiptLine> lines;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money furtherTax;

  /// Tax the BUYER withheld and will deposit themselves, under s.153 or a
  /// similar provision. It comes off the total, so it has to appear on the
  /// paper: a bill whose printed parts do not add up to its printed total,
  /// with nothing explaining the gap, is a bill the customer and the auditor
  /// both read as wrong.
  final Money withholding;
  final Money extraCharges;
  final Money roundOff;
  final Money total;

  final List<ReceiptTender> tenders;
  final Money paid;
  final Money balance;
  final Money change;

  /// What the customer owed before this bill, when they are on udhaar.
  final Money? previousBalance;

  final List<String> footerLines;

  /// A QR image the merchant's own bank issued and the merchant imported.
  /// Rendered as a picture. Never generated.
  final MonoBitmap? bankQr;

  final bool isReprint;

  int get itemCount => lines.length;

  Money get runningBalance =>
      previousBalance == null ? balance : previousBalance! + balance;
}

/// A one-bit-per-pixel bitmap, row-major, MSB first.
///
/// Thermal printers have no shaping engine and no bidi. The community ESC/POS
/// capability database lists seventy code pages and not one of them is Urdu,
/// so Nastaliq — and even CP1256 — comes out as unshaped isolated letters
/// printed left to right. Anything that is not Latin has to arrive as pixels.
final class MonoBitmap {
  const MonoBitmap({
    required this.width,
    required this.height,
    required this.bits,
  });

  final int width;
  final int height;

  /// `((width + 7) ~/ 8) * height` bytes. A set bit is a black dot.
  final Uint8List bits;

  int get bytesPerRow => (width + 7) ~/ 8;
}

/// How wide the paper is.
enum ReceiptPaper {
  /// 80 mm, 576 dots, 48 columns in Font A. The counter default: a major
  /// Karachi distributor lists a fourteen-SKU 80 mm category and no 58 mm
  /// category at all — every 58 mm unit sits under Bluetooth portables.
  mm80(columns: 48, dots: 576),

  /// 80 mm, 576 dots, but 42 columns.
  ///
  /// The same paper as [mm80] and a different answer, which is why the width
  /// is a per-printer setting rather than a property of the roll. Whether an
  /// 80 mm printer takes 42 or 48 depends on its ROM font and its margins, and
  /// two machines that look identical on a shelf disagree. ESC/POS has no
  /// query for it, so the setup screen prints a ruler and the shopkeeper reads
  /// the answer off the paper.
  ///
  /// Getting it wrong is not subtle: a 48-column layout on a 42-column printer
  /// wraps every total onto the next line.
  mm80Narrow(columns: 42, dots: 576),

  /// 58 mm, 384 dots, 32 columns. The pocket Bluetooth printers.
  mm58(columns: 32, dots: 384);

  const ReceiptPaper({required this.columns, required this.dots});

  final int columns;
  final int dots;
}

/// Renders a receipt for a device that is going to print it.
abstract interface class ReceiptRenderer {
  /// Bytes for a thermal printer.
  ///
  /// [drawn] carries pictures of the lines the printer's own font cannot say
  /// — Urdu, in practice — keyed by the exact string the layout produced.
  /// A line found there is sent as a raster image; every other line takes the
  /// crisp, small font path. See `unprintableLines` in `pk_platform` for what
  /// a caller has to draw, and why nothing else will do.
  Uint8List toThermalBytes(
    ReceiptData data, {
    ReceiptPaper paper,
    bool openDrawer,
    Map<String, MonoBitmap> drawn,
  });

  /// The lines of this receipt the printer's own font cannot say, as the
  /// exact strings [toThermalBytes] will look up in its `drawn` map.
  ///
  /// On the interface because only a renderer knows what it emits — it prints
  /// its own copy of the shop name and skips the layout's, so a survey done
  /// anywhere else names a line nobody prints and the caller draws a picture
  /// that is thrown away.
  Set<String> unprintableLines(ReceiptData data, {ReceiptPaper paper});

  /// The same receipt as plain text, one string per printed line.
  ///
  /// On the interface rather than only on the implementation, because the
  /// preview screen must show the strings the printer is actually handed. A
  /// separate "nicer" on-screen layout is a second implementation that
  /// drifts, and the first anybody notices is a customer's printed copy
  /// disagreeing with what the shopkeeper approved.
  List<String> toPreview(ReceiptData data, {ReceiptPaper paper});

  /// A PDF, for sharing over WhatsApp or saving.
  ///
  /// [unicodeFont] is a TrueType face for the glyphs the PDF base fonts do
  /// not have. A PDF carries its own fonts — the file is read on somebody
  /// else's phone, with no system fallback to lean on — so without one, Urdu
  /// does not degrade to question marks the way the thermal path does. It
  /// simply is not there.
  Future<Uint8List> toPdf(ReceiptData data, {Uint8List? unicodeFont});
}
