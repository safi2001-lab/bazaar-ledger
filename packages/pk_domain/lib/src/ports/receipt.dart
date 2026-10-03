import 'dart:convert';
import 'dart:typed_data';

import 'package:pk_money/pk_money.dart';

import '../tax/service_tax.dart'
    show percentOfBp, serviceTaxAuthorityOf, serviceTaxLabel;

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
    this.logoImage,
  });

  /// The same shop, with the picture of its logo that goes on a PDF (M51).
  ReceiptShop withLogoImage(Uint8List? image) => ReceiptShop(
    name: name,
    addressLine1: addressLine1,
    city: city,
    phone: phone,
    ntn: ntn,
    strn: strn,
    raastAlias: raastAlias,
    bankName: bankName,
    bankAccountTitle: bankAccountTitle,
    bankIban: bankIban,
    logo: logo,
    logoImage: image,
  );

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

  /// The shop's logo as the owner picked it, a small JPEG or PNG, for the
  /// head of a PDF bill (M51). Null when there is none.
  ///
  /// Separate from [logo] because the two papers want different pictures:
  /// a till roll prints one-bit dots and a PDF prints the colours the shop
  /// chose. A logo is not put on the till roll at all — a photographed
  /// logo thresholded to black and white is a smudge above the shop's name.
  final Uint8List? logoImage;
}

/// One labelled tax on a receipt's totals: "PRA 8% (card)" and its amount
/// (M59).
final class ReceiptTaxLine {
  const ReceiptTaxLine({required this.label, required this.amount});

  final String label;
  final Money amount;
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
    this.tax,
    this.qtyWords,
  });

  final String name;
  final String qtyDisplay;
  final String unitCode;
  final Rate rate;
  final Money amount;
  final Money discount;
  final bool isFreeItem;

  /// What this line's tax was, for the tax-invoice layout (M51). Null when
  /// nobody read it, and the layouts that do not show tax never ask.
  final ReceiptLineTax? tax;

  /// The quantity in the item's packs, when the line was not sold in them
  /// (M45): "2 ctn 5 pc" beside "53 pcs". Null when the figure already says
  /// it, and for a weight: "1.5 kg x 300.00" stays as M56 left it, plain
  /// enough to multiply out, and a 58 mm roll is not lengthened to say "1 kg
  /// 500 g" under it.
  ///
  /// Printed as well as the figure, never instead of it: the rate is per
  /// [unitCode], and the customer checks the line by multiplying the two.
  final String? qtyWords;

  /// The same line with its tax read in.
  ReceiptLine withTax(ReceiptLineTax? value) => ReceiptLine(
    name: name,
    qtyDisplay: qtyDisplay,
    unitCode: unitCode,
    rate: rate,
    amount: amount,
    discount: discount,
    isFreeItem: isFreeItem,
    tax: value,
    qtyWords: qtyWords,
  );
}

/// One line's tax, the way a registered seller's invoice has to show it
/// (M51).
///
/// Section 23 of the Sales Tax Act asks every registered seller's invoice for
/// the value excluding tax, the sales tax and the value including tax, and
/// FBR's own invoice rules add the rate. A customer who claims the tax back
/// claims it line by line, so a total at the foot is not enough.
final class ReceiptLineTax {
  const ReceiptLineTax({
    required this.valueExclTax,
    required this.salesTax,
    this.rateBp,
    this.furtherTax = Money.zero,
    this.hsCode,
    this.rateParts = const [],
  });

  /// M61: the rates a service line was taxed at, part by part, when the
  /// province's tax on it came in more than one — a bill paid part by card
  /// and part in cash is taxed 8% on the card's share and 16% on the rest.
  /// Empty, or one part, for every other line.
  final List<ReceiptRatePart> rateParts;

  /// After every discount, before any tax: what the tax was charged on.
  final Money valueExclTax;

  /// Sales tax, and the provincial or special taxes charged in its place.
  final Money salesTax;

  /// The sales-tax rate in basis points (18% is 1800), or null when no
  /// sales tax applied to the line at all.
  final int? rateBp;

  /// Charged to an unregistered buyer on top of sales tax.
  final Money furtherTax;

  /// The PCT heading, where the item has one.
  final String? hsCode;

  Money get valueInclTax => valueExclTax + salesTax + furtherTax;

  /// `18%`, `8.5%`, `0%`; a dash where no rate applied.
  ///
  /// Integer arithmetic on basis points, so the 8th Schedule's 12.75% prints
  /// as exactly that and never as a float's idea of it.
  String get rateLabel {
    // M61: a line taxed at two rates says both, "16% / 8%", never the
    // higher beside an amount that is a blend of the two.
    if (rateParts.length > 1) {
      return [for (final p in rateParts) percentOfBp(p.rateBp)].join(' / ');
    }
    final bp = rateBp;
    if (bp == null) return '-';
    final whole = bp ~/ 100;
    final part = bp % 100;
    if (part == 0) return '$whole%';
    final digits = part.toString().padLeft(2, '0');
    return '$whole.${digits.endsWith('0') ? digits[0] : digits}%';
  }

  /// M61: how a line taxed at two rates was split, in words for the line's
  /// own row of a tax invoice: "PRA 16% on Rs 537.04, 8% (card) on Rs
  /// 462.96". Null for a line taxed at one rate, which the Rate column
  /// already says in full.
  String? get rateSplit {
    if (rateParts.length < 2) return null;
    final first = rateParts.first;
    final who = serviceTaxAuthorityOf(first.code);
    // The authority once, at the front: "PRA 16% on .., 8% (card) on ..".
    String label(ReceiptRatePart p) {
      final full = serviceTaxLabel(p.code, p.rateBp);
      return identical(p, first) || !full.startsWith('$who ')
          ? full
          : full.substring(who.length + 1);
    }

    return [for (final p in rateParts) '${label(p)} on ${p.base}'].join(', ');
  }
}

/// One rate of a line taxed at more than one (M61): the tax code it was
/// charged under (`PRA_CARD`), its rate, and the part of the line's value
/// it was charged on.
final class ReceiptRatePart {
  const ReceiptRatePart({
    required this.code,
    required this.rateBp,
    required this.base,
  });

  final String code;
  final int rateBp;
  final Money base;
}

/// Which sheet of a bill this is (M51).
///
/// A wholesaler's carbon book has three: the original goes with the buyer,
/// the duplicate with the goods, the triplicate stays in the book. Goods sent
/// up-country leave through a transport adda, and the driver is handed a
/// fourth — the transporter's copy, which lists what is in the sacks and to
/// whom, and carries no price at all, because what the buyer pays is not the
/// driver's business and a sheet with prices on it is a sheet that gets
/// photographed at the adda and passed to a competitor.
enum ReceiptCopy {
  original,
  duplicate,
  triplicate,
  transporter;

  /// What the sheet says about itself on paper, in the English and Roman
  /// Urdu every bill is printed in.
  String get mark => switch (this) {
    original => 'ORIGINAL / ASAL',
    duplicate => 'DUPLICATE / DOBARA COPY',
    triplicate => 'TRIPLICATE / TEESRI COPY',
    transporter => 'TRANSPORTER / DELIVERY COPY',
  };

  /// The word in a file's title, so a file list says what the page says.
  String get titleWord => switch (this) {
    original => 'ORIGINAL',
    duplicate => 'DUPLICATE',
    triplicate => 'TRIPLICATE',
    transporter => 'TRANSPORTER COPY',
  };

  /// Whether this sheet carries any money at all.
  bool get showsMoney => this != transporter;
}

/// How the goods on a bill travel, from the bill's own non-fiscal fields
/// (M51). A bilty number arrives after the bill is printed, which is why the
/// schema keeps these editable on a posted bill.
final class ReceiptTransport {
  const ReceiptTransport({
    this.transporter,
    this.vehicleNo,
    this.biltyNo,
    this.shipTo,
  });

  /// The transport company or adda: "Daewoo Cargo", "Niazi Goods, Badami
  /// Bagh".
  final String? transporter;

  /// The truck or Mazda's registration.
  final String? vehicleNo;

  /// The goods receipt number the adda gave. The buyer collects the goods
  /// at the other end with it.
  final String? biltyNo;

  /// Where the goods go, when that is not the buyer's own address.
  final String? shipTo;

  static const none = ReceiptTransport();

  bool get isEmpty => [
    transporter,
    vehicleNo,
    biltyNo,
    shipTo,
  ].every((v) => v == null || v.trim().isEmpty);
}

/// A customer's khata at the moment one bill was made (M51).
///
/// What a credit customer wants on the paper is not the bill alone but where
/// it leaves them: what they owed before it, what this bill adds, and what
/// they owe now. "Pichhla baqaya, is bill, kul baqaya" is how a shopkeeper
/// says it, and how a paper khata reads.
///
/// Always as it stood when the bill was made, never as it stands today. A
/// duplicate printed next month carries the same three figures the original
/// did, because a second sheet that disagrees with the first is a sheet one
/// party will say was forged. What the customer owes today is the khata's
/// question, and the khata answers it.
final class KhataAtBill {
  const KhataAtBill({required this.before, required this.thisBill});

  /// The khata balance just before the bill. Negative when the shop was
  /// holding the customer's money as an advance.
  final Money before;

  /// What the bill itself left on the khata when it was made: its total less
  /// what was paid at the counter.
  final Money thisBill;

  /// Where the bill left them.
  Money get after => before + thisBill;
}

/// What a bill's paper needs that the receipt read does not carry (M51).
///
/// Read separately rather than added to [ReceiptData] by the receipt read,
/// so the paper the counter has printed since M2 is untouched unless a
/// design asks for more.
final class BillExtras {
  const BillExtras({
    required this.docType,
    this.partyId,
    this.partyPhone,
    this.partyAddress,
    this.partyNtn,
    this.partyStrn,
    this.transport = ReceiptTransport.none,
    this.lineTaxes = const [],
    this.khata,
  });

  /// `sale_invoice`, `delivery_challan`, `quotation`, `purchase_bill`...
  final String docType;

  /// Null for a walk-in.
  final String? partyId;
  final String? partyPhone;

  /// As the bill recorded it, or — for a bill made before the counter
  /// recorded one — the party's own, read today. The second is a fallback,
  /// not a rule: a party who moved is a party whose old bill now names the
  /// new shop, which is the myBillBook complaint this product set out not to
  /// repeat.
  final String? partyAddress;
  final String? partyNtn;
  final String? partyStrn;

  final ReceiptTransport transport;

  /// One per line, in line order, the same order the receipt read uses.
  final List<ReceiptLineTax> lineTaxes;

  /// The khata at the bill, for a sale to a named customer. Null for a
  /// walk-in and for every other kind of paper.
  final KhataAtBill? khata;

  bool get isSaleInvoice => docType == 'sale_invoice';

  /// Whether goods leave the shop on this paper, so a transporter's copy of
  /// it means something.
  bool get sendsGoods =>
      docType == 'sale_invoice' || docType == 'delivery_challan';
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
    this.fbrInvoiceNo,
    this.fbrPending = false,
    this.isReprint = false,
    this.isCancelled = false,
    this.docTitle = 'Invoice',
    this.docLabel = 'Bill No',
    this.partyLabel = 'Customer',
    this.copy,
    this.customerAddress,
    this.customerNtn,
    this.customerStrn,
    this.transport = ReceiptTransport.none,
    this.billOwed,
    this.paymentQr,
    this.serviceTaxes = const [],
  });

  /// The province's tax on the bill's services, one row per rate (M59):
  /// "PRA 16%", "PRA 8% (card)". Part of [tax], which the paper prints as
  /// sales tax less these, so the printed parts still add up to the total.
  final List<ReceiptTaxLine> serviceTaxes;

  /// The federal sales tax: [tax] less the province's on services.
  Money get federalTax =>
      tax - Money.sum([for (final t in serviceTaxes) t.amount]);

  /// What the paper is: Invoice, or Quotation. A quotation printed as an
  /// invoice is a bill for goods that never left the shop.
  final String docTitle;

  /// How the number is labelled on paper: "Bill No", "Quotation No".
  final String docLabel;

  /// Who [customerName] is, on paper: "Customer", or "Supplier" on a purchase
  /// bill (M30). A delivery shown back with the mill as its "Customer" is a
  /// bill that says the shop sold the mill its own rice.
  final String partyLabel;

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
  ///
  /// With [billOwed], the "pichhla baqaya / is bill / kul baqaya" block
  /// (M51): the khata as it stood when the bill was made, never as it
  /// stands on the day a copy is printed. See [KhataAtBill].
  final Money? previousBalance;

  /// What this bill itself left on the khata when it was made. Null means
  /// [balance], which is the same figure on the day of the sale and drifts
  /// from it as payments come in afterwards.
  final Money? billOwed;

  final List<String> footerLines;

  /// A QR image the merchant's own bank issued and the merchant imported,
  /// as one-bit dots for the till roll. Rendered as a picture. Never
  /// generated.
  final MonoBitmap? bankQr;

  /// The same QR as the owner picked it — a small PNG or JPEG — for the foot
  /// of a PDF bill (M51). Never generated either: the scheme identifier in
  /// a payment QR belongs to the State Bank's licensed PSO/PSPs, and minting
  /// one is an offence under s.56 PS&EFT Act. This is a picture of the QR
  /// the shop's own bank or wallet gave it, reprinted, which s.4.2 of the
  /// SBP QR standard contemplates.
  final Uint8List? paymentQr;

  /// Which sheet this is, when somebody chose (M51). Null leaves it to
  /// [isReprint], which is what every bill printed before M51 relied on.
  final ReceiptCopy? copy;

  /// Where the customer is, and their tax registration, for the bill-to
  /// block, the tax invoice and the transporter's copy (M51).
  final String? customerAddress;
  final String? customerNtn;
  final String? customerStrn;

  /// How the goods travel, printed whenever any of it is known (M51).
  final ReceiptTransport transport;

  /// FBR's own number for this bill once FBR has accepted it (M19),
  /// printed with a QR of it.
  final String? fbrInvoiceNo;

  /// Sent to FBR and not yet answered.
  final bool fbrPending;

  /// A copy of a bill whose original has already gone to paper: printed
  /// "DUPLICATE" (M30), as the shop's own carbon book says on its second
  /// sheet. Set when a printed bill is sent again, never on the first copy.
  final bool isReprint;

  /// A bill that was cancelled after it was made, marked so on what is sent
  /// (M30). A cancelled bill sent on without the mark reads, to a customer
  /// holding it, exactly like one they still owe on.
  ///
  /// Set by whoever sends it, never by the receipt read itself: the paper a
  /// thermal printer hands over keeps printing as it did on the day.
  final bool isCancelled;

  int get itemCount => lines.length;

  /// The mark this sheet carries, if any: the one chosen, or the duplicate
  /// mark M30 puts on a bill whose original has already gone to paper.
  ReceiptCopy? get copyMark =>
      copy ?? (isReprint ? ReceiptCopy.duplicate : null);

  /// Whether any money is printed on this sheet. Only the transporter's copy
  /// carries none.
  bool get showsMoney => copy?.showsMoney ?? true;

  /// The "pichhla baqaya / is bill / kul baqaya" block, when this bill has
  /// one to print.
  KhataAtBill? get khata => previousBalance == null
      ? null
      : KhataAtBill(before: previousBalance!, thisBill: billOwed ?? balance);

  /// The same receipt, marked, dressed or filled in further.
  ///
  /// Every field this does not name is carried across, so a mark added on
  /// the way out of the phone never costs the paper a line it had.
  ReceiptData copyWith({
    bool? isReprint,
    bool? isCancelled,
    ReceiptShop? shop,
    List<ReceiptLine>? lines,
    String? customerPhone,
    Money? previousBalance,
    Money? billOwed,
    List<String>? footerLines,
    MonoBitmap? bankQr,
    Uint8List? paymentQr,
    ReceiptCopy? copy,
    String? customerAddress,
    String? customerNtn,
    String? customerStrn,
    ReceiptTransport? transport,
  }) => ReceiptData(
    shop: shop ?? this.shop,
    docNo: docNo,
    dateTimeLabel: dateTimeLabel,
    lines: lines ?? this.lines,
    subtotal: subtotal,
    total: total,
    tenders: tenders,
    paid: paid,
    balance: balance,
    change: change,
    cashierName: cashierName,
    customerName: customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    discount: discount,
    tax: tax,
    furtherTax: furtherTax,
    withholding: withholding,
    extraCharges: extraCharges,
    roundOff: roundOff,
    previousBalance: previousBalance ?? this.previousBalance,
    billOwed: billOwed ?? this.billOwed,
    footerLines: footerLines ?? this.footerLines,
    bankQr: bankQr ?? this.bankQr,
    paymentQr: paymentQr ?? this.paymentQr,
    fbrInvoiceNo: fbrInvoiceNo,
    fbrPending: fbrPending,
    isReprint: isReprint ?? this.isReprint,
    isCancelled: isCancelled ?? this.isCancelled,
    docTitle: docTitle,
    docLabel: docLabel,
    partyLabel: partyLabel,
    copy: copy ?? this.copy,
    customerAddress: customerAddress ?? this.customerAddress,
    customerNtn: customerNtn ?? this.customerNtn,
    customerStrn: customerStrn ?? this.customerStrn,
    transport: transport ?? this.transport,
    serviceTaxes: serviceTaxes,
  );

  Money get runningBalance => khata?.after ?? balance;
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
  ///
  /// [design] is how the shop wants its bills to look (M51): the layout, the
  /// colour and the page size. The till roll has no design; it is the same
  /// 48 columns for every shop.
  Future<Uint8List> toPdf(
    ReceiptData data, {
    Uint8List? unicodeFont,
    BillDesign design,
  });
}

/// The four ways a PDF bill can look (M51).
///
/// Few on purpose. Vyapar offers a dozen, and what shopkeepers ask for in
/// its reviews is not a thirteenth but that the one they picked keeps the
/// Urdu readable and the totals where they expect them.
enum BillTheme {
  /// Centred, black on white, the shop's colour in its rules: what a bill
  /// book from the stationer looks like.
  classic,

  /// A band of the shop's colour across the top with the name on it.
  modern,

  /// Small type and tight rows, so a forty-line wholesale bill takes one
  /// sheet where it would take two.
  compact,

  /// A sales tax invoice with every particular s.23 of the Sales Tax Act
  /// asks for: the seller's and the buyer's names, addresses and
  /// registration numbers, and for every line the value excluding tax, the
  /// rate, the tax and the value including it.
  taxInvoice;

  static BillTheme parse(Object? value) => BillTheme.values.firstWhere(
    (t) => t.name == value,
    orElse: () => BillTheme.classic,
  );
}

/// The colours a shop can put on its bills (M51), as ARGB.
///
/// A handful of presets rather than a colour wheel: every one of these is
/// dark enough that white type on it reads and that it prints as a clear
/// grey on a black-and-white office printer, which an arbitrary colour is
/// not.
enum BillAccent {
  ink(0xFF1F2937),
  blue(0xFF1D4ED8),
  green(0xFF047857),
  maroon(0xFF9F1239),
  orange(0xFFC2410C),
  purple(0xFF6D28D9);

  const BillAccent(this.argb);

  final int argb;

  static BillAccent parse(Object? value) => BillAccent.values.firstWhere(
    (a) => a.name == value,
    orElse: () => BillAccent.ink,
  );
}

/// A5 or A4. A5 is half a sheet and what most shops share; A4 is what a
/// tax invoice to a company is expected on.
enum BillPageSize {
  a5,
  a4;

  static BillPageSize parse(Object? value) => BillPageSize.values.firstWhere(
    (p) => p.name == value,
    orElse: () => BillPageSize.a5,
  );
}

/// How a shop wants its bills to look, kept once per firm (M51).
///
/// Stored as JSON in the firm's own `settings` row, so it travels with the
/// books to a new phone and to a second counter. Read forgivingly: a value a
/// later version wrote, or one cut short, falls back to the default for
/// that field rather than failing — a design is never a reason a bill does
/// not go out.
final class BillDesign {
  const BillDesign({
    this.theme = BillTheme.classic,
    this.accent = BillAccent.ink,
    this.pageSize = BillPageSize.a5,
    this.showPreviousBalance = true,
    this.qrOnThermal = false,
    this.footerLines = defaultFooter,
  });

  /// The line every bill has said since M2, in the firm's settings key
  /// `bill.design`.
  static const settingKey = 'bill.design';

  /// The thank-you line the receipt read puts on every bill a customer is
  /// handed. Replaced, never added to, by the shop's own footer.
  static const defaultThanks = 'Shukriya! Phir tashreef laayen';
  static const defaultFooter = [defaultThanks];

  /// At most this many footer lines, of at most [footerLineMax] characters:
  /// a footer is a sentence or two, and a pasted paragraph on a 58 mm roll
  /// is a foot of paper.
  static const footerLinesMax = 4;
  static const footerLineMax = 96;

  final BillTheme theme;
  final BillAccent accent;
  final BillPageSize pageSize;

  /// Whether a sale to a named customer prints the khata block.
  final bool showPreviousBalance;

  /// Whether the shop's payment QR picture also goes on the till roll, as
  /// one-bit dots. Off by default: a QR thresholded from a photograph scans
  /// on most rolls, but the shop should see one come out before trusting it.
  final bool qrOnThermal;

  /// The thank-you, return-policy and "goods once sold" lines, in whatever
  /// script the shop typed them. Empty means no footer at all.
  final List<String> footerLines;

  BillDesign copyWith({
    BillTheme? theme,
    BillAccent? accent,
    BillPageSize? pageSize,
    bool? showPreviousBalance,
    bool? qrOnThermal,
    List<String>? footerLines,
  }) => BillDesign(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    pageSize: pageSize ?? this.pageSize,
    showPreviousBalance: showPreviousBalance ?? this.showPreviousBalance,
    qrOnThermal: qrOnThermal ?? this.qrOnThermal,
    footerLines: footerLines ?? this.footerLines,
  );

  /// [lines] as they are kept: trimmed, blanks dropped, each cut to
  /// [footerLineMax] and at most [footerLinesMax] of them.
  static List<String> tidyFooter(Iterable<String> lines) => [
    for (final line in lines.map((l) => l.trim()).where((l) => l.isNotEmpty))
      line.length <= footerLineMax ? line : line.substring(0, footerLineMax),
  ].take(footerLinesMax).toList();

  String toJson() => jsonEncode({
    'theme': theme.name,
    'accent': accent.name,
    'page': pageSize.name,
    'previousBalance': showPreviousBalance,
    'qrOnThermal': qrOnThermal,
    'footer': footerLines,
  });

  static BillDesign fromJson(String? json) {
    if (json == null || json.trim().isEmpty) return const BillDesign();
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const BillDesign();
    }
    if (decoded is! Map) return const BillDesign();
    final footer = decoded['footer'];
    return BillDesign(
      theme: BillTheme.parse(decoded['theme']),
      accent: BillAccent.parse(decoded['accent']),
      pageSize: BillPageSize.parse(decoded['page']),
      showPreviousBalance: decoded['previousBalance'] is bool
          ? decoded['previousBalance'] as bool
          : true,
      qrOnThermal: decoded['qrOnThermal'] == true,
      footerLines: footer is List
          ? tidyFooter(footer.whereType<String>())
          : defaultFooter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BillDesign &&
      other.theme == theme &&
      other.accent == accent &&
      other.pageSize == pageSize &&
      other.showPreviousBalance == showPreviousBalance &&
      other.qrOnThermal == qrOnThermal &&
      _sameLines(other.footerLines, footerLines);

  @override
  int get hashCode => Object.hash(
    theme,
    accent,
    pageSize,
    showPreviousBalance,
    qrOnThermal,
    Object.hashAll(footerLines),
  );

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// [base] made into the paper this shop hands over (M51): the sheet chosen,
/// the party's address and tax numbers, how the goods travel, each line's
/// tax, the khata block, the shop's own footer, its logo and its payment QR.
///
/// Pure, so every rule below is tested without a database:
///
/// * The khata block goes only on a sale bill to a named customer, only
///   when [BillDesign.showPreviousBalance] is on, and only when there is
///   something to say — a regular who owed nothing and paid in full gets no
///   "0.00 / 0.00 / 0.00".
/// * The shop's footer replaces the thank-you line the receipt read adds,
///   and nothing else: the free plan's "made with" line and a quotation's
///   terms stay where they were. A purchase bill shown back has no
///   thank-you line, so the shop's footer does not go on the mill's paper.
/// * The logo and the QR are pictures the owner chose. Nothing here draws
///   one.
ReceiptData dressBill(
  ReceiptData base, {
  BillExtras? extras,
  BillDesign design = const BillDesign(),
  ReceiptCopy? copy,
  Uint8List? logo,
  Uint8List? paymentQr,
  MonoBitmap? paymentQrDots,
}) {
  var lines = base.lines;
  final taxes = extras?.lineTaxes ?? const <ReceiptLineTax>[];
  // Zipped by position: both reads order by line number over the same
  // rows. A count that disagrees means one of them skipped a line, and a
  // tax column shifted by one row is worse than none.
  if (taxes.length == lines.length && taxes.isNotEmpty) {
    lines = [for (var i = 0; i < lines.length; i++) lines[i].withTax(taxes[i])];
  }

  final footer = <String>[];
  for (final line in base.footerLines) {
    if (line == BillDesign.defaultThanks) {
      footer.addAll(design.footerLines);
    } else {
      footer.add(line);
    }
  }

  final khata = extras?.khata;
  final printsKhata =
      design.showPreviousBalance &&
      extras != null &&
      extras.isSaleInvoice &&
      extras.partyId != null &&
      khata != null &&
      !(khata.before.isZero && khata.thisBill.isZero);

  return base.copyWith(
    copy: copy,
    lines: lines,
    footerLines: footer,
    // On the transporter's copy only. The driver rings the buyer from the
    // adda; a customer handed their own bill does not need their own number
    // printed on it, and the till roll stays the length it was.
    customerPhone: copy == ReceiptCopy.transporter && extras?.partyId != null
        ? extras?.partyPhone
        : null,
    customerAddress: extras?.partyAddress,
    customerNtn: extras?.partyNtn,
    customerStrn: extras?.partyStrn,
    transport: extras?.transport,
    previousBalance: printsKhata ? khata.before : null,
    billOwed: printsKhata ? khata.thisBill : null,
    shop: logo == null ? null : base.shop.withLogoImage(logo),
    paymentQr: paymentQr,
    bankQr: paymentQrDots,
  );
}

/// The few lines that travel beside a transporter's copy (M51): whose goods,
/// which bill, how many lines, and the bilty and truck — never an amount.
///
/// The buyer collects goods from the adda with the bilty number, so this is
/// exactly what they need on WhatsApp; the price is already on their own
/// copy.
String transportMessage(ReceiptData receipt) {
  final t = receipt.transport;
  bool has(String? s) => s != null && s.trim().isNotEmpty;
  return [
    receipt.shop.name,
    'Maal ki tafseel: ${receipt.docTitle} ${receipt.docNo}',
    if (has(receipt.customerName)) 'Kis ke liye: ${receipt.customerName}',
    'Date: ${receipt.dateTimeLabel}',
    '${receipt.itemCount} item(s)',
    if (has(t.transporter)) 'Transporter: ${t.transporter}',
    if (has(t.vehicleNo)) 'Gaari no: ${t.vehicleNo}',
    if (has(t.biltyNo)) 'Bilty no: ${t.biltyNo}',
    if (has(t.shipTo)) 'Ship to: ${t.shipTo}',
  ].join('\n');
}
